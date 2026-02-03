#!/bin/bash
# State management for codex-review plugin
# Usage: codex-state.sh {show|reset|get|set} [args]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

STATE_DIR="$(get_state_dir)"
STATE_FILE="$STATE_DIR/state.json"

cmd_show() {
    if [[ -f "$STATE_FILE" ]]; then
        cat "$STATE_FILE"
    else
        echo '{"session_id":"","phase":"","iteration":0,"max_iterations":3,"last_review_status":"","last_review_timestamp":"","task_description":""}'
    fi
}

cmd_reset() {
    if [[ "${1:-}" == "--full" ]]; then
        rm -rf "$STATE_DIR/notes"/*.md
        rm -f "$STATE_FILE"
        mkdir -p "$STATE_DIR/notes"
        touch "$STATE_DIR/notes/.gitkeep"
        echo "Full reset complete."
    else
        local session_id task_desc
        session_id="$(read_state_field "session_id")"
        task_desc="$(read_state_field "task_description")"
        write_state "{
  \"session_id\": \"$session_id\",
  \"phase\": \"\",
  \"iteration\": 0,
  \"max_iterations\": $CODEX_MAX_ITERATIONS,
  \"last_review_status\": \"\",
  \"last_review_timestamp\": \"\",
  \"task_description\": \"$task_desc\"
}"
        echo "Reset complete (session_id preserved)."
    fi
}

cmd_get() {
    local field="${1:?Usage: codex-state.sh get <field>}"
    local val
    val="$(read_state_field "$field")"
    if [[ -z "$val" ]]; then
        val="$(read_state_number "$field")"
    fi
    echo "$val"
}

cmd_set() {
    local field="${1:?Usage: codex-state.sh set <field> <value>}"
    local value="${2:?Usage: codex-state.sh set <field> <value>}"

    if [[ ! -f "$STATE_FILE" ]]; then
        write_state "{
  \"session_id\": \"\",
  \"phase\": \"\",
  \"iteration\": 0,
  \"max_iterations\": 3,
  \"last_review_status\": \"\",
  \"last_review_timestamp\": \"\",
  \"task_description\": \"\"
}"
    fi

    local tmp
    tmp=$(sed "s|\"$field\"[[:space:]]*:[[:space:]]*\"[^\"]*\"|\"$field\": \"$value\"|" "$STATE_FILE")
    echo "$tmp" > "$STATE_FILE"
    echo "Set $field = $value"
}

# --- Load config for defaults ---
load_config

# --- Main ---
case "${1:-}" in
    show)   cmd_show ;;
    reset)  cmd_reset "${2:-}" ;;
    get)    cmd_get "${2:-}" ;;
    set)    cmd_set "${2:-}" "${3:-}" ;;
    *)
        echo "Usage: codex-state.sh {show|reset|get|set} [args]"
        echo "  show              Current state (JSON)"
        echo "  reset             Reset iterations/phase (keep session_id)"
        echo "  reset --full      Full reset + delete notes"
        echo "  get <field>       Get a single field"
        echo "  set <field> <val> Set a field (e.g. session_id)"
        exit 1
        ;;
esac
