#!/bin/sh
# End-to-end tests for the codex-review plugin.
#
# OPT-IN — only runs when CODEX_E2E=1 is set in the environment. Otherwise
# exits 0 with a skip message so CI and casual runs don't burn quota.
#
# Prerequisites:
#   - `codex` binary installed and authenticated (always required)
#   - `claude` binary installed and authenticated (only for the `stale` scenario)
#   - Network access
#
# Usage:
#   CODEX_E2E=1 sh plugins/codex-review/test/test-e2e.sh                  # all scenarios
#   CODEX_E2E=1 sh plugins/codex-review/test/test-e2e.sh approve          # only approve
#   CODEX_E2E=1 sh plugins/codex-review/test/test-e2e.sh approve reject   # subset
#   CODEX_E2E=1 sh plugins/codex-review/test/test-e2e.sh stale            # only stale
#
# Available scenarios:
#
#   approve  — Repo A: approve cycle (2 codex calls: init + plan)
#     A1 cold-start  — fresh repo, no init, hook → deny ("No verdict found")
#     A2 init + plan — trivial "Do nothing" fixture → APPROVED
#     A3 hook allow  — verdict.txt present → hook outputs allow + deletes it
#     A4 stale guard — second hook call → deny ("No verdict found")
#
#   reject   — Repo B: reject then resubmit (3 codex calls: init + 2 plans)
#     B1 init + reject plan → CHANGES_REQUESTED (via explicit fixture request)
#     B2 hook deny   — message must contain CHANGES_REQUESTED + "resubmit"
#     B3 resubmit plan — approve fixture in SAME session → APPROVED
#     B4 hook allow  — stale reject was cleared before step B3
#
#   stale    — Repo S: stale-state survival test (1 real claude run + ~2 codex calls)
#     Pre-seeds .codex-review/main with stale verdict.txt=APPROVED + state.json
#     + notes from a fake completed prior task. Invokes real claude in plan
#     mode with the plugin loaded. Asserts that the plugin notices the stale
#     state, runs init, archives the old artifacts, and runs a fresh review
#     for the new task — i.e. the stale verdict does NOT silently auto-approve.
#
# Total cost (all scenarios): ~5 codex calls + 1 claude run, ~3-5 minutes.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROD_SCRIPTS="$SCRIPT_DIR/../skills/codex-review/scripts"
HOOK="$PROD_SCRIPTS/auto-approve-plan.sh"
REVIEW_CMD="$PROD_SCRIPTS/codex-review.sh"
STATE_CMD="$PROD_SCRIPTS/codex-state.sh"
FIXTURES="$SCRIPT_DIR/test-fixtures"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"  # plugins/codex-review

# --- Opt-in gate ---
if [ "${CODEX_E2E:-}" != "1" ]; then
    echo "SKIP: test-e2e.sh requires CODEX_E2E=1 (real codex / claude calls)." >&2
    echo "      Run: CODEX_E2E=1 sh $0 [scenarios...]" >&2
    exit 0
fi

# --- Pre-req check (codex always required) ---
if ! command -v codex >/dev/null 2>&1; then
    echo "ERROR: codex binary not found in PATH." >&2
    exit 1
fi

if [ ! -f "$FIXTURES/approve_plan.md" ] || [ ! -f "$FIXTURES/reject_plan.md" ]; then
    echo "ERROR: fixtures missing in $FIXTURES" >&2
    exit 1
fi

# --- Scenario selection ---
ALL_SCENARIOS="approve reject stale"
if [ $# -eq 0 ]; then
    SELECTED="$ALL_SCENARIOS"
else
    SELECTED="$*"
    # Validate names
    for s in $SELECTED; do
        case " $ALL_SCENARIOS " in
            *" $s "*) ;;
            *)
                echo "ERROR: unknown scenario '$s'. Available: $ALL_SCENARIOS" >&2
                exit 1
                ;;
        esac
    done
fi

PASS=0
FAIL=0

# ============================
# Helpers
# ============================

assert_contains() {
    test_name="$1"
    haystack="$2"
    needle="$3"
    case "$haystack" in
        *"$needle"*)
            PASS=$((PASS + 1))
            printf "  PASS: %s\n" "$test_name"
            ;;
        *)
            FAIL=$((FAIL + 1))
            printf "  FAIL: %s\n" "$test_name"
            printf "    expected substring: %s\n" "$needle"
            printf "    in: %s\n" "$haystack"
            ;;
    esac
}

assert_eq() {
    test_name="$1"
    expected="$2"
    actual="$3"
    if [ "$actual" = "$expected" ]; then
        PASS=$((PASS + 1))
        printf "  PASS: %s\n" "$test_name"
    else
        FAIL=$((FAIL + 1))
        printf "  FAIL: %s\n" "$test_name"
        printf "    expected: %s\n" "$expected"
        printf "    actual:   %s\n" "$actual"
    fi
}

run_hook_in() {
    (cd "$1" && echo '{}' | sh "$HOOK" 2>/dev/null) || true
}

init_test_repo() {
    # $1 = dir
    mkdir -p "$1"
    (
        cd "$1"
        git init -q -b main
        git config user.email "e2e@test.com"
        git config user.name "E2E Test"
        git commit -q --allow-empty -m "init"
        mkdir -p .codex-review
        printf 'AUTO_REVIEW=true\n' > .codex-review/config.env
    )
}

TMPDIR_BASE="${TMPDIR:-/tmp}"

# ============================
# Scenario: approve cycle
# ============================
scenario_approve() {
    printf "\n=== Scenario approve: cycle ===\n"
    RA="$TMPDIR_BASE/test-e2e-approve-$$"
    init_test_repo "$RA"

    # --- A1: cold-start (no init yet, no verdict) ---
    printf "A1: cold-start hook should deny\n"
    out_a1="$(run_hook_in "$RA")"
    assert_contains "hook denies before any review" "$out_a1" '"behavior":"deny"'
    assert_contains "cold-start message" "$out_a1" "No Codex plan verdict found"

    # --- A2: init + plan with approve fixture ---
    printf "A2: init + plan (approve fixture)\n"
    (
        cd "$RA"
        bash "$REVIEW_CMD" init "e2e approve test" >/dev/null 2>&1
    ) || { echo "  FAIL: codex-review.sh init errored" >&2; FAIL=$((FAIL + 1)); rm -rf "$RA"; return; }

    approve_plan="$(cat "$FIXTURES/approve_plan.md")"
    (
        cd "$RA"
        bash "$REVIEW_CMD" plan "$approve_plan" >/dev/null 2>&1
    ) || { echo "  FAIL: codex-review.sh plan errored" >&2; FAIL=$((FAIL + 1)); rm -rf "$RA"; return; }

    status_a2="$(cd "$RA" && bash "$STATE_CMD" get last_review_status 2>/dev/null | tr -d '[:space:]')"
    assert_eq "state.last_review_status = APPROVED" "APPROVED" "$status_a2"

    state_dir_a="$(cd "$RA" && bash "$STATE_CMD" dir)"
    if [ -f "$state_dir_a/verdict.txt" ]; then
        verdict_a="$(tr -d '[:space:]' < "$state_dir_a/verdict.txt")"
        assert_eq "verdict.txt = APPROVED" "APPROVED" "$verdict_a"
    else
        FAIL=$((FAIL + 1))
        printf "  FAIL: verdict.txt missing at %s\n" "$state_dir_a"
    fi

    # --- A3: hook allow + cleanup ---
    printf "A3: hook allow + delete verdict\n"
    out_a3="$(run_hook_in "$RA")"
    assert_contains "hook allows after APPROVED" "$out_a3" '"behavior":"allow"'
    if [ -f "$state_dir_a/verdict.txt" ]; then
        FAIL=$((FAIL + 1))
        printf "  FAIL: verdict.txt not deleted after allow\n"
    else
        PASS=$((PASS + 1))
        printf "  PASS: verdict.txt deleted after allow\n"
    fi

    # --- A4: stale guard — second hook call must cold-start deny ---
    printf "A4: second hook call → cold-start deny\n"
    out_a4="$(run_hook_in "$RA")"
    assert_contains "second call denies" "$out_a4" '"behavior":"deny"'
    assert_contains "second call cold-start msg" "$out_a4" "No Codex plan verdict found"

    rm -rf "$RA"
}

# ============================
# Scenario: reject then resubmit
# ============================
scenario_reject() {
    printf "\n=== Scenario reject: reject → resubmit cycle ===\n"
    RB="$TMPDIR_BASE/test-e2e-reject-$$"
    init_test_repo "$RB"

    # --- B1: init + plan with reject fixture ---
    printf "B1: init + plan (reject fixture)\n"
    (
        cd "$RB"
        bash "$REVIEW_CMD" init "e2e reject test" >/dev/null 2>&1
    ) || { echo "  FAIL: codex-review.sh init errored" >&2; FAIL=$((FAIL + 1)); rm -rf "$RB"; return; }

    reject_plan="$(cat "$FIXTURES/reject_plan.md")"
    (
        cd "$RB"
        bash "$REVIEW_CMD" plan "$reject_plan" >/dev/null 2>&1
    ) || true  # CHANGES_REQUESTED still exits 0; only technical errors exit non-zero

    status_b1="$(cd "$RB" && bash "$STATE_CMD" get last_review_status 2>/dev/null | tr -d '[:space:]')"
    assert_eq "state.last_review_status = CHANGES_REQUESTED" "CHANGES_REQUESTED" "$status_b1"

    state_dir_b="$(cd "$RB" && bash "$STATE_CMD" dir)"
    if [ -f "$state_dir_b/verdict.txt" ]; then
        verdict_b1="$(tr -d '[:space:]' < "$state_dir_b/verdict.txt")"
        assert_eq "verdict.txt = CHANGES_REQUESTED" "CHANGES_REQUESTED" "$verdict_b1"
    else
        FAIL=$((FAIL + 1))
        printf "  FAIL: verdict.txt missing at %s\n" "$state_dir_b"
    fi

    # --- B2: hook denies with resubmit message ---
    printf "B2: hook deny with resubmit message\n"
    out_b2="$(run_hook_in "$RB")"
    assert_contains "hook denies after reject" "$out_b2" '"behavior":"deny"'
    assert_contains "verdict value in deny msg" "$out_b2" "CHANGES_REQUESTED"
    assert_contains "resubmit instruction" "$out_b2" "resubmit"

    # --- B3: resubmit with approve fixture in SAME session ---
    printf "B3: resubmit plan (approve fixture, same session)\n"
    approve_plan="$(cat "$FIXTURES/approve_plan.md")"
    (
        cd "$RB"
        bash "$REVIEW_CMD" plan "$approve_plan" >/dev/null 2>&1
    ) || { echo "  FAIL: resubmit plan errored" >&2; FAIL=$((FAIL + 1)); rm -rf "$RB"; return; }

    status_b3="$(cd "$RB" && bash "$STATE_CMD" get last_review_status 2>/dev/null | tr -d '[:space:]')"
    assert_eq "resubmit state = APPROVED" "APPROVED" "$status_b3"

    # --- B4: hook allow after resubmit ---
    printf "B4: hook allow after resubmit\n"
    out_b4="$(run_hook_in "$RB")"
    assert_contains "hook allows after resubmit" "$out_b4" '"behavior":"allow"'

    rm -rf "$RB"
}

# ============================
# Scenario: stale state survival (real claude)
# ============================
# Reproduces the scenario user is worried about: in main, complete feature A,
# branch off, come back to main weeks later, start unrelated feature B.
# The .codex-review/main/ dir still has stale verdict.txt=APPROVED + state.json
# + notes from feature A.
#
# We run a real claude session asking it to use the codex-review workflow for
# a fresh task. The skill should:
#   1. Call `codex-review.sh init` → archive_previous_session moves the stale
#      state.json/verdict.txt/notes into .codex-review/archive/<ts>/.
#   2. Run a fresh plan review under a new session id.
#
# Pass = the skill correctly archives stale artifacts and writes a fresh
# state.json describing the NEW task. The previous APPROVED verdict must NOT
# leak into the new task's directory.
#
# NOTE on the production hook: in non-interactive (-p) mode, PermissionRequest
# hooks do not fire and ExitPlanMode is hard-blocked by the harness regardless
# of any hook decision. So we cannot exercise the auto-approve hook end-to-end
# from a -p test. This scenario instead exercises the SKILL's init/plan path,
# which is the layer responsible for archiving stale state in the first place.
# The hook behavior itself is covered by test-auto-approve-plan.sh + test-integration.sh.
scenario_stale() {
    printf "\n=== Scenario stale: stale artifacts must not poison a fresh review ===\n"

    if ! command -v claude >/dev/null 2>&1; then
        FAIL=$((FAIL + 1))
        printf "  FAIL: claude binary not found in PATH (required for stale scenario)\n"
        return
    fi

    RS="$TMPDIR_BASE/test-e2e-stale-$$"
    init_test_repo "$RS"

    # Create a target file for the new task
    (
        cd "$RS"
        printf '# Test repo\n' > README.md
        git add README.md
        git commit -q -m "add README"
    )

    # Pre-seed stale state simulating "Feature A finished long ago"
    state_dir_s="$RS/.codex-review/main"
    mkdir -p "$state_dir_s/notes"

    cat > "$state_dir_s/state.json" <<'JSON'
{
  "session_id": "sess_old_feature_a_stale",
  "phase": "code",
  "iteration": 3,
  "max_iterations": 5,
  "last_review_status": "APPROVED",
  "last_review_timestamp": "2026-01-01T00:00:00Z",
  "task_description": "OLD FEATURE A — stale, must be archived"
}
JSON
    printf 'APPROVED' > "$state_dir_s/verdict.txt"
    cat > "$state_dir_s/notes/plan-review-1.md" <<'NOTE'
# Plan Review #1 (STALE — from feature A)
Date: 2026-01-01T00:00:00Z

APPROVED (stale)
NOTE

    # Backdate the stale files so a future TTL-based fix can also detect them
    touch -d "2026-01-01 00:00:00" "$state_dir_s/state.json" \
        "$state_dir_s/verdict.txt" "$state_dir_s/notes/plan-review-1.md"

    printf "  invoking real claude (this may take 2-5 min — runs codex init + plan)\n"
    printf "  plugin: %s\n" "$PLUGIN_ROOT"

    claude_log="$RS/claude.log"
    # The prompt explicitly invokes the codex-review skill trigger so the
    # workflow runs. Without this trigger, the skill would not auto-load.
    # Tools: Bash (for codex-review.sh), Edit/Read/Write for the file edit.
    # acceptEdits permission so claude doesn't get blocked editing README.
    # 5 min hard timeout — codex init + first plan review on a small repo
    # typically completes in 90-180s; budget 2x for safety.
    (
        cd "$RS"
        timeout 300 claude -p \
            --plugin-dir "$PLUGIN_ROOT" \
            --allowedTools "Bash,Edit,Read,Write" \
            --permission-mode acceptEdits \
            "Use codex-review workflow to plan and apply this change: add a single line containing 'Hello, world!' to README.md after the existing heading. Treat this as a fresh task — any pre-existing .codex-review state belongs to unrelated prior work and must be archived before starting." \
            > "$claude_log" 2>&1
    ) || true

    printf "  claude exited (log: %s)\n" "$claude_log"

    # === Assertions ===
    # The minimum proof that the skill handled stale state is:
    #   1. archive/<ts>/state.json EXISTS and contains the OLD task marker
    #      (proof archive_previous_session ran during init)
    #   2. main/state.json has been REPLACED with a new task_description
    #      (proof a fresh session was started)
    #   3. The OLD APPROVED verdict.txt is no longer in main/ as-is
    #      (proof the stale verdict was either archived or overwritten)
    # We do NOT require README.md to be modified or a plan-review note to exist —
    # those are nice-to-have and may be cut short by the hard timeout.

    # 1. Stale state archived
    archived_state="$(find "$RS/.codex-review/archive" -mindepth 2 -name state.json 2>/dev/null | head -1)"
    if [ -n "$archived_state" ] && grep -q "OLD FEATURE A" "$archived_state" 2>/dev/null; then
        PASS=$((PASS + 1))
        printf "  PASS: stale state archived with original task marker\n"
    else
        FAIL=$((FAIL + 1))
        printf "  FAIL: stale state.json NOT archived — init did not run\n"
        printf "    .codex-review tree:\n"
        find "$RS/.codex-review" -maxdepth 3 2>/dev/null | sed 's/^/      /'
        printf "    last 30 log lines:\n"
        tail -30 "$claude_log" 2>/dev/null | sed 's/^/      /'
    fi

    # 2. main/state.json reflects a NEW task (not the stale one)
    new_task="$(grep -o '"task_description"[[:space:]]*:[[:space:]]*"[^"]*"' \
        "$state_dir_s/state.json" 2>/dev/null | head -1)"
    case "$new_task" in
        *"OLD FEATURE A"*)
            FAIL=$((FAIL + 1))
            printf "  FAIL: main/state.json still contains stale task_description\n"
            ;;
        "")
            FAIL=$((FAIL + 1))
            printf "  FAIL: main/state.json missing or unreadable\n"
            ;;
        *)
            PASS=$((PASS + 1))
            printf "  PASS: main/state.json describes a fresh task\n"
            ;;
    esac

    # 3. Old stale verdict.txt is no longer present unchanged in main/
    #    (it was either archived or overwritten by a new review)
    if [ -f "$state_dir_s/verdict.txt" ]; then
        # If a verdict.txt is present, it must NOT be the stale one — i.e.
        # there must be an archived copy of the original stale verdict.
        archived_verdict="$(find "$RS/.codex-review/archive" -mindepth 2 -name verdict.txt 2>/dev/null | head -1)"
        if [ -n "$archived_verdict" ]; then
            PASS=$((PASS + 1))
            printf "  PASS: old verdict.txt was archived; current verdict belongs to fresh review\n"
        else
            FAIL=$((FAIL + 1))
            printf "  FAIL: verdict.txt present in main/ but no archived copy — stale leak\n"
        fi
    else
        PASS=$((PASS + 1))
        printf "  PASS: stale verdict.txt no longer in main/\n"
    fi

    # 4. Bonus (informational, non-fatal) — fresh plan-review note exists
    fresh_note="$(find "$state_dir_s/notes" -type f -name "plan-review-*.md" 2>/dev/null \
        | xargs -I{} grep -L "STALE" {} 2>/dev/null | head -1)"
    if [ -n "$fresh_note" ]; then
        printf "  INFO: fresh plan-review note created (full plan review ran)\n"
    else
        printf "  INFO: no fresh plan-review note — claude finished init but plan review may have been cut short\n"
    fi

    rm -rf "$RS"
}

# ============================
# Run selected scenarios
# ============================
for s in $SELECTED; do
    case "$s" in
        approve) scenario_approve ;;
        reject)  scenario_reject ;;
        stale)   scenario_stale ;;
    esac
done

# ============================
# Summary
# ============================
printf "\n=== E2E results: %d passed, %d failed ===\n" "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
