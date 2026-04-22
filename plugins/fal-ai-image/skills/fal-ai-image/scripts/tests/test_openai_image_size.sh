#!/bin/sh
# Test OpenAI image_size helper.

set -e

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="$(cd "$TESTS_DIR/.." && pwd)"
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/fal_image_size_test.XXXXXX")

cleanup() {
    rm -rf "$TMP_DIR"
}

trap cleanup EXIT INT TERM

cat > "$TMP_DIR/.env" <<'EOF'
FAL_KEY=test-key
FAL_IMAGE_PROVIDER=openai
EOF

FAL_AI_IMAGE_CONFIG_FILE="$TMP_DIR/.env"
export FAL_AI_IMAGE_CONFIG_FILE

# shellcheck disable=SC1091
. "$SCRIPTS_DIR/common.sh"

load_config >/dev/null

square=$(openai_image_size_json "" "1:1" "1K" "false")
[ "$square" = '{"width":1024,"height":1024}' ]

landscape=$(openai_image_size_json "" "4:3" "2K" "false")
[ "$landscape" = '{"width":2048,"height":1536}' ]

preset=$(openai_image_size_json "portrait_16_9" "1:1" "1K" "false")
[ "$preset" = '"portrait_16_9"' ]

auto_size=$(openai_image_size_json "" "auto" "1K" "true")
[ "$auto_size" = '"auto"' ]

custom=$(openai_image_size_json "1280x720" "1:1" "1K" "false")
[ "$custom" = '{"width":1280,"height":720}' ]

if openai_image_size_json "1000x700" "1:1" "1K" "false" >/dev/null 2>&1; then
    echo "Expected invalid custom size to fail"
    exit 1
fi

echo "test_openai_image_size: all passed"
