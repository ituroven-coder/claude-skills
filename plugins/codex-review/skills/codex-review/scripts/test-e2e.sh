#!/bin/sh
# End-to-end tests against the real `codex` CLI.
#
# OPT-IN — only runs when CODEX_E2E=1 is set in the environment. Otherwise
# exits 0 with a skip message so CI and casual runs don't burn codex quota.
#
# Prerequisites (set up these once before running):
#   - `codex` binary installed and authenticated
#   - Network access
#
# Run:
#   CODEX_E2E=1 sh plugins/codex-review/skills/codex-review/scripts/test-e2e.sh
#
# Scenarios (grouped into 2 repos to minimize codex calls):
#
#   Repo A — approve cycle (2 codex calls: init + plan)
#     A1 cold-start  — fresh repo, no init, hook → deny ("No verdict found")
#     A2 init + plan — trivial "Do nothing" fixture → APPROVED
#     A3 hook allow  — verdict.txt present → hook outputs allow + deletes it
#     A4 stale guard — second hook call → deny ("No verdict found")
#
#   Repo B — reject then resubmit (3 codex calls: init + reject plan + approve plan)
#     B1 init + reject plan → CHANGES_REQUESTED (via explicit fixture request)
#     B2 hook deny   — message must contain CHANGES_REQUESTED + "resubmit"
#     B3 resubmit plan — approve fixture in SAME session → APPROVED
#     B4 hook allow  — stale reject was cleared before step B3
#
# Total: ~5 codex calls, ~1–3 minutes real time depending on model.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$SCRIPT_DIR/auto-approve-plan.sh"
REVIEW_CMD="$SCRIPT_DIR/codex-review.sh"
STATE_CMD="$SCRIPT_DIR/codex-state.sh"
FIXTURES="$SCRIPT_DIR/test-fixtures"

# --- Opt-in gate ---
if [ "${CODEX_E2E:-}" != "1" ]; then
    echo "SKIP: test-e2e.sh requires CODEX_E2E=1 (real codex calls)." >&2
    echo "      Run: CODEX_E2E=1 sh $0" >&2
    exit 0
fi

# --- Pre-req check ---
if ! command -v codex >/dev/null 2>&1; then
    echo "ERROR: codex binary not found in PATH." >&2
    exit 1
fi

if [ ! -f "$FIXTURES/approve_plan.md" ] || [ ! -f "$FIXTURES/reject_plan.md" ]; then
    echo "ERROR: fixtures missing in $FIXTURES" >&2
    exit 1
fi

PASS=0
FAIL=0

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
# Repo A — approve cycle
# ============================
printf "\n=== Repo A: approve cycle ===\n"
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
) || { echo "  FAIL: codex-review.sh init errored" >&2; exit 1; }

approve_plan="$(cat "$FIXTURES/approve_plan.md")"
(
    cd "$RA"
    bash "$REVIEW_CMD" plan "$approve_plan" >/dev/null 2>&1
) || { echo "  FAIL: codex-review.sh plan errored" >&2; exit 1; }

# Verify state and verdict file
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

# ============================
# Repo B — reject then resubmit
# ============================
printf "\n=== Repo B: reject → resubmit cycle ===\n"
RB="$TMPDIR_BASE/test-e2e-reject-$$"
init_test_repo "$RB"

# --- B1: init + plan with reject fixture ---
printf "B1: init + plan (reject fixture)\n"
(
    cd "$RB"
    bash "$REVIEW_CMD" init "e2e reject test" >/dev/null 2>&1
) || { echo "  FAIL: codex-review.sh init errored" >&2; exit 1; }

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
) || { echo "  FAIL: resubmit plan errored" >&2; exit 1; }

status_b3="$(cd "$RB" && bash "$STATE_CMD" get last_review_status 2>/dev/null | tr -d '[:space:]')"
assert_eq "resubmit state = APPROVED" "APPROVED" "$status_b3"

# --- B4: hook allow after resubmit ---
printf "B4: hook allow after resubmit\n"
out_b4="$(run_hook_in "$RB")"
assert_contains "hook allows after resubmit" "$out_b4" '"behavior":"allow"'

rm -rf "$RB"

# ============================
# Summary
# ============================
printf "\n=== E2E results: %d passed, %d failed ===\n" "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
