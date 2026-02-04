#!/bin/bash
# Common functions for codex-review plugin

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Anti-recursion guard (deterministic, primary defense) ---
guard_recursion() {
    if [[ "${CODEX_REVIEWER:-}" == "1" ]]; then
        echo "ERROR: Recursion detected (CODEX_REVIEWER=1). Aborting." >&2
        exit 1
    fi
}

# --- Project root via git ---
get_project_root() {
    git rev-parse --show-toplevel 2>/dev/null || {
        echo "ERROR: Not inside a git repository." >&2
        exit 1
    }
}

# --- State directory (.codex-review/ in project root) ---
get_state_dir() {
    local root
    root="$(get_project_root)"
    local state_dir="$root/.codex-review"
    mkdir -p "$state_dir/notes"
    touch "$state_dir/.gitkeep" "$state_dir/notes/.gitkeep"
    echo "$state_dir"
}

# --- Load config (project config.env → env vars → defaults) ---
load_config() {
    local state_dir
    state_dir="$(get_state_dir)"
    local config_file="$state_dir/config.env"

    if [[ -f "$config_file" ]]; then
        # shellcheck disable=SC1090
        source "$config_file"
    fi

    CODEX_MODEL="${CODEX_MODEL:-gpt-5.2}"
    CODEX_REASONING_EFFORT="${CODEX_REASONING_EFFORT:-high}"
    CODEX_MAX_ITERATIONS="${CODEX_MAX_ITERATIONS:-3}"
    CODEX_YOLO="${CODEX_YOLO:-true}"
}

# --- Read a field from state.json (no jq dependency) ---
read_state_field() {
    local field="$1"
    local state_dir
    state_dir="$(get_state_dir)"
    local state_file="$state_dir/state.json"

    if [[ ! -f "$state_file" ]]; then
        echo ""
        return
    fi

    grep -o "\"$field\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$state_file" \
        | head -1 \
        | sed 's/.*:[[:space:]]*"//' \
        | tr -d '"'
}

# --- Read numeric field from state.json ---
read_state_number() {
    local field="$1"
    local state_dir
    state_dir="$(get_state_dir)"
    local state_file="$state_dir/state.json"

    if [[ ! -f "$state_file" ]]; then
        echo "0"
        return
    fi

    local val
    val=$(grep -o "\"$field\"[[:space:]]*:[[:space:]]*[0-9]*" "$state_file" \
        | head -1 \
        | sed 's/.*:[[:space:]]*//')
    echo "${val:-0}"
}

# --- Effective session_id: config.env → state.json ---
get_effective_session_id() {
    local sid="${CODEX_SESSION_ID:-}"
    if [[ -z "$sid" ]]; then
        sid="$(read_state_field "session_id")"
    fi
    echo "$sid"
}

# --- Write state.json ---
write_state() {
    local json="$1"
    local state_dir
    state_dir="$(get_state_dir)"
    echo "$json" > "$state_dir/state.json"
}

# --- Write STATUS.md from current state.json ---
write_status() {
    local state_dir
    state_dir="$(get_state_dir)"
    local status_file="$state_dir/STATUS.md"

    local task phase iteration max_iter review_status
    task="$(read_state_field "task_description")"
    phase="$(read_state_field "phase")"
    iteration="$(read_state_number "iteration")"
    max_iter="$(read_state_number "max_iterations")"
    review_status="$(read_state_field "last_review_status")"

    {
        echo "# Active Codex Review"
        echo "- Task: ${task:-not set}"
        echo "- Phase: ${phase:-initialized}"
        echo "- Iteration: ${iteration}/${max_iter}"
        echo "- Last status: ${review_status:-pending}"
        echo "- Journal: \`.codex-review/notes/\`"
    } > "$status_file"
}

# --- Remove STATUS.md (review complete or full reset) ---
remove_status() {
    local state_dir
    state_dir="$(get_state_dir)"
    rm -f "$state_dir/STATUS.md"
}

# --- Check codex is installed ---
check_codex_installed() {
    if ! command -v codex &>/dev/null; then
        echo "ERROR: 'codex' CLI not found in PATH." >&2
        echo "Install: npm install -g @openai/codex" >&2
        exit 1
    fi
}
