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
config_file="$repo_root/.codex-review/config.env"
AUTO_REVIEW="false"
if [ -f "$config_file" ]; then
    # Extract AUTO_REVIEW value from config
    _val="$(grep -E '^AUTO_REVIEW=' "$config_file" 2>/dev/null | tail -1 | sed 's/^AUTO_REVIEW=//' | tr -d '"' | tr -d "'")"
    if [ -n "$_val" ]; then
        AUTO_REVIEW="$_val"
    fi
fi

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
if [ -f "$verdict_file" ]; then
    verdict="$(tr -d '[:space:]' < "$verdict_file")"
    if [ "$verdict" = "APPROVED" ]; then
        cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}
EOF
        exit 0
    fi
fi

# --- Deny: redirect to codex-review skill ---
cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"Load skill 'codex-review' and follow the auto-workflow to review the plan before exiting plan mode."}}}
EOF
