#!/bin/sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
COMMON_SH="$SKILL_DIR/scripts/common.sh"
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/xr_config_test.XXXXXX")

cleanup() {
    rm -rf "$TMP_DIR"
}

trap cleanup EXIT INT TERM

cat > "$TMP_DIR/.env" <<'EOF'
XAI_API_KEY=test-key
XAI_MODEL=grok-test
X_DEFAULT_CATEGORY=openai
X_TOPICS_OPENAI=GPT,ChatGPT,OpenAI,Codex,gpt 5.4
X_TOPICS_ANTHROPIC=Claude,Anthropic,ClaudeCode,Claude Code
X_ACCOUNTS_OPENAI_LABEL="OpenAI ecosystem"
X_ACCOUNTS_OPENAI=sama,OpenAI
EOF

# shellcheck disable=SC1090
. "$COMMON_SH"

CONFIG_FILE="$TMP_DIR/.env"
CACHE_DIR="$TMP_DIR/cache"
RUNS_DIR="$CACHE_DIR/runs"
INDEX_FILE="$CACHE_DIR/index.jsonl"

load_config >/dev/null

[ "$XAI_API_KEY" = "test-key" ]
[ "$XAI_MODEL" = "grok-test" ]
[ "$X_DEFAULT_CATEGORY" = "openai" ]
[ "$X_TOPICS_OPENAI" = "GPT,ChatGPT,OpenAI,Codex,gpt 5.4" ]
[ "$X_TOPICS_ANTHROPIC" = "Claude,Anthropic,ClaudeCode,Claude Code" ]
[ "$X_ACCOUNTS_OPENAI_LABEL" = "OpenAI ecosystem" ]
[ "$X_ACCOUNTS_OPENAI" = "sama,OpenAI" ]
