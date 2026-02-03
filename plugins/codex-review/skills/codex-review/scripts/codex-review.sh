#!/bin/bash
# Main codex-review script: init, plan, code
# Usage: codex-review.sh <init|plan|code> "description" [--max-iter N]
#
# Exit codes:
#   0 — review received (APPROVED or CHANGES_REQUESTED)
#   1 — technical error (codex unavailable, invalid session_id)
#   2 — escalation (max iterations reached)
#   3 — no session (Claude should ask user to create one)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

# --- Anti-recursion (primary defense) ---
guard_recursion

# --- Parse arguments ---
COMMAND="${1:-}"
if [[ -z "$COMMAND" ]]; then
    echo "Usage: codex-review.sh <init|plan|code> \"description\" [--max-iter N]" >&2
    exit 1
fi
shift

DESCRIPTION=""
MAX_ITER=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --max-iter)
            MAX_ITER="$2"
            shift 2
            ;;
        *)
            DESCRIPTION="$1"
            shift
            ;;
    esac
done

if [[ -z "$DESCRIPTION" && "$COMMAND" != "status" ]]; then
    echo "ERROR: Description is required." >&2
    echo "Usage: codex-review.sh <init|plan|code> \"description\" [--max-iter N]" >&2
    exit 1
fi

# --- Load config & state ---
load_config
check_codex_installed

STATE_DIR="$(get_state_dir)"
STATE_FILE="$STATE_DIR/state.json"

MAX_ITERATIONS="${MAX_ITER:-$CODEX_MAX_ITERATIONS}"
SESSION_ID="$(get_effective_session_id)"

# --- Build yolo flags ---
build_yolo_flag() {
    if [[ "$CODEX_YOLO" == "true" ]]; then
        echo "--yolo"
    fi
}

# --- Extract session_id from codex output ---
extract_session_id() {
    local output="$1"
    # codex prints session id in various formats; try common patterns
    local sid
    sid=$(echo "$output" | grep -oE 'sess_[a-zA-Z0-9_-]+' | head -1)
    if [[ -z "$sid" ]]; then
        sid=$(echo "$output" | grep -oE '[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}' | head -1)
    fi
    echo "$sid"
}

# --- Save review note ---
save_note() {
    local phase="$1"
    local iteration="$2"
    local content="$3"
    local note_file="$STATE_DIR/notes/${phase}-review-${iteration}.md"
    {
        echo "# $(echo "$phase" | awk '{print toupper(substr($0,1,1)) substr($0,2)}') Review #${iteration}"
        echo "Date: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        echo ""
        echo "$content"
    } > "$note_file"
}

# --- Update state.json ---
update_state() {
    local phase="$1"
    local iteration="$2"
    local status="$3"
    local timestamp
    timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    local task_desc
    task_desc="$(read_state_field "task_description")"

    write_state "{
  \"session_id\": \"$SESSION_ID\",
  \"phase\": \"$phase\",
  \"iteration\": $iteration,
  \"max_iterations\": $MAX_ITERATIONS,
  \"last_review_status\": \"$status\",
  \"last_review_timestamp\": \"$timestamp\",
  \"task_description\": \"$task_desc\"
}"
}

# --- Determine review status from codex response ---
parse_review_status() {
    local response="$1"
    if echo "$response" | grep -qiE '(^|\W)APPROVED(\W|$)'; then
        echo "APPROVED"
    else
        echo "CHANGES_REQUESTED"
    fi
}

# --- Format output ---
print_result() {
    local phase="$1"
    local iteration="$2"
    local max="$3"
    local session="$4"
    local response="$5"
    local status="$6"

    echo ""
    echo "=== CODEX REVIEW ==="
    echo "Phase: $phase"
    echo "Iteration: ${iteration}/${max}"
    echo "Session: $session"
    echo ""
    echo "$response"
    echo ""
    echo "=== END REVIEW ==="
    echo "Status: $status"
}

# =====================
# COMMAND: init
# =====================
cmd_init() {
    local prompt="$DESCRIPTION"

    # Warn if config.env already has a session
    if [[ -n "${CODEX_SESSION_ID:-}" ]]; then
        echo "WARNING: CODEX_SESSION_ID is already set in config.env: $CODEX_SESSION_ID" >&2
        echo "Init will create a NEW session. Update config.env afterwards or remove CODEX_SESSION_ID to use state.json." >&2
    fi

    echo "Creating Codex session..." >&2

    local output
    output=$(CODEX_REVIEWER=1 codex exec \
        --model "$CODEX_MODEL" \
        $(build_yolo_flag) \
        "$prompt" 2>&1) || {
        echo "ERROR: Failed to create Codex session." >&2
        echo "$output" >&2
        exit 1
    }

    local new_session_id
    new_session_id="$(extract_session_id "$output")"

    if [[ -z "$new_session_id" ]]; then
        echo "WARNING: Could not extract session_id from codex output." >&2
        echo "Output from codex:" >&2
        echo "$output" >&2
        echo "" >&2
        echo "Please set session_id manually:" >&2
        echo "  bash codex-state.sh set session_id <YOUR_SESSION_ID>" >&2
        exit 1
    fi

    SESSION_ID="$new_session_id"
    local task_desc
    task_desc="$(read_state_field "task_description")"

    write_state "{
  \"session_id\": \"$SESSION_ID\",
  \"phase\": \"initialized\",
  \"iteration\": 0,
  \"max_iterations\": $MAX_ITERATIONS,
  \"last_review_status\": \"\",
  \"last_review_timestamp\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\",
  \"task_description\": \"$task_desc\"
}"

    echo "Session created: $SESSION_ID"
}

# =====================
# COMMAND: plan / code
# =====================
cmd_review() {
    local phase="$1"

    # Check session exists
    if [[ -z "$SESSION_ID" ]]; then
        echo ""
        echo "=== CODEX REVIEW ==="
        echo "Phase: $phase"
        echo ""
        echo "No active Codex session found."
        echo ""
        echo "=== END REVIEW ==="
        echo "Status: NO_SESSION"
        exit 3
    fi

    # Check iteration limit
    local current_iteration
    current_iteration="$(read_state_number "iteration")"
    local next_iteration=$((current_iteration + 1))

    if [[ $next_iteration -gt $MAX_ITERATIONS ]]; then
        echo ""
        echo "=== CODEX REVIEW ==="
        echo "Phase: $phase"
        echo "Iteration: ${next_iteration}/${MAX_ITERATIONS}"
        echo "Session: $SESSION_ID"
        echo ""
        echo "Maximum iterations ($MAX_ITERATIONS) reached."
        echo "Review notes are in: $STATE_DIR/notes/"
        echo ""
        echo "=== END REVIEW ==="
        echo "Status: ESCALATE"
        exit 2
    fi

    # Build prompt for Codex
    local skill_path
    skill_path="$(cd "$SCRIPT_DIR/.." && pwd)"

    local codex_prompt="You are reviewing work by Claude Code on this project.
Phase: $phase

Description from Claude:
$DESCRIPTION

Instructions:
- Review the described changes in the context of this repository
- If acceptable, respond with APPROVED
- If changes needed, provide specific actionable feedback
- You can inspect the code yourself — you're in the same directory
- The codex-review skill is at: $skill_path"

    # Call codex with resume
    echo "Sending $phase for review (iteration ${next_iteration}/${MAX_ITERATIONS})..." >&2

    local output
    output=$(CODEX_REVIEWER=1 codex exec \
        --model "$CODEX_MODEL" \
        -c "model_reasoning_effort=\"$CODEX_REASONING_EFFORT\"" \
        $(build_yolo_flag) \
        resume "$SESSION_ID" \
        "$codex_prompt" 2>&1) || {
        local exit_code=$?
        echo "ERROR: Codex exec failed (exit $exit_code)." >&2
        echo "$output" >&2
        update_state "$phase" "$next_iteration" "ERROR"
        exit 1
    }

    # Parse status
    local status
    status="$(parse_review_status "$output")"

    # Save note
    save_note "$phase" "$next_iteration" "$output"

    # Update state
    update_state "$phase" "$next_iteration" "$status"

    # Print result
    print_result "$phase" "$next_iteration" "$MAX_ITERATIONS" "$SESSION_ID" "$output" "$status"
}

# --- Main ---
case "$COMMAND" in
    init)   cmd_init ;;
    plan)   cmd_review "plan" ;;
    code)   cmd_review "code" ;;
    *)
        echo "Usage: codex-review.sh <init|plan|code> \"description\" [--max-iter N]" >&2
        echo "" >&2
        echo "Commands:" >&2
        echo "  init \"prompt\"        Create a new Codex session" >&2
        echo "  plan \"description\"   Submit plan for review" >&2
        echo "  code \"description\"   Submit code for review" >&2
        echo "" >&2
        echo "Exit codes:" >&2
        echo "  0 — Review received (APPROVED or CHANGES_REQUESTED)" >&2
        echo "  1 — Technical error" >&2
        echo "  2 — Escalation (max iterations)" >&2
        echo "  3 — No session" >&2
        exit 1
        ;;
esac
