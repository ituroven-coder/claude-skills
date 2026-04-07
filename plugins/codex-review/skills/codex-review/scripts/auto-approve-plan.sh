#!/bin/sh
# PermissionRequest hook for ExitPlanMode.
# When AUTO_REVIEW=true: auto-approve if verdict.txt=APPROVED,
# otherwise deny with instruction to load codex-review skill.
# When AUTO_REVIEW!=true: no output (normal UI dialog).

set -e

# --- Locate git repo root ---
git_common_dir="$(git rev-parse --git-common-dir 2>/dev/null)" || exit 0
repo_root="$(cd "$git_common_dir/.." && pwd)"

# --- Read config.env ---
# Source in a subshell to match common.sh behavior exactly (handles `export`,
# leading whitespace, quoted values, etc). Side effects stay isolated.
config_file="$repo_root/.codex-review/config.env"
AUTO_REVIEW="$( . "$config_file" 2>/dev/null; echo "${AUTO_REVIEW:-false}" )"

# Not auto mode — exit silently (normal UI dialog)
if [ "$AUTO_REVIEW" != "true" ]; then
    exit 0
fi

# --- Find branch state dir ---
branch="$(git symbolic-ref --short HEAD 2>/dev/null)" \
    || branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" \
    || branch="detached"
branch_slug="$(echo "$branch" | tr '/' '-')"
verdict_file="$repo_root/.codex-review/$branch_slug/verdict.txt"

# --- Check verdict ---
# Three branches with distinct deny messages so Claude can recover correctly:
#   - APPROVED          → allow + cleanup verdict
#   - present, not APPROVED → deny "resubmit" (already mid-cycle)
#   - missing           → deny "load skill + run plan review" (cold start)
if [ -f "$verdict_file" ]; then
    # Strip whitespace, then restrict to [A-Za-z0-9_] so the value is safe to
    # interpolate into a JSON string literal below.
    verdict="$(tr -d '[:space:]' < "$verdict_file" | tr -cd '[:alnum:]_')"
    if [ "$verdict" = "APPROVED" ]; then
        rm -f "$verdict_file"
        cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}
EOF
        exit 0
    fi
    # Verdict present but not APPROVED — Claude already ran review, must resubmit.
    # Default to "unknown" if file existed but content was empty/garbage.
    [ -n "$verdict" ] || verdict="unknown"
    printf '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"Codex plan verdict is %s, not APPROVED. Address feedback and resubmit via '\''codex-review.sh plan --plan-file <path>'\'' — do NOT call ExitPlanMode until APPROVED."}}}\n' "$verdict"
    exit 0
fi

# --- Deny: no verdict at all — cold start, instruct to load skill ---
cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"No Codex plan verdict found. Load skill 'codex-review' and run plan review before ExitPlanMode: init + plan --plan-file <path>."}}}
EOF
