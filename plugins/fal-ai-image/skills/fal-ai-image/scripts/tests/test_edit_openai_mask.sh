#!/bin/sh
# Test that edit.sh forwards mask_url to openai/gpt-image-2/edit.

set -e

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="$(cd "$TESTS_DIR/.." && pwd)"
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/fal_image_edit_mask.XXXXXX")

cleanup() {
    rm -rf "$TMP_DIR"
}

trap cleanup EXIT INT TERM

cat > "$TMP_DIR/.env" <<'EOF'
FAL_KEY=test-key
FAL_IMAGE_PROVIDER=openai
EOF

mkdir -p "$TMP_DIR/bin"

cat > "$TMP_DIR/bin/curl" <<'EOF'
#!/bin/sh
set -e

LOG_DIR="${FAL_TEST_LOG_DIR:?}"
URL=""
DATA=""
NEXT_IS_DATA="false"

for arg in "$@"; do
    if [ "$NEXT_IS_DATA" = "true" ]; then
        DATA="$arg"
        NEXT_IS_DATA="false"
        continue
    fi

    case "$arg" in
        -d)
            NEXT_IS_DATA="true"
            ;;
        http://*|https://*)
            URL="$arg"
            ;;
    esac
done

printf '%s\n' "$URL" >> "$LOG_DIR/url.txt"
[ -n "$DATA" ] && printf '%s\n' "$DATA" > "$LOG_DIR/payload.json"

case "$URL" in
    */status)
        printf '{"status":"COMPLETED"}'
        ;;
    */requests/req-test)
        printf '{"images":[{"url":"https://example.com/result.png","content_type":"image/png","file_name":"result.png"}]}'
        ;;
    *)
        printf '{"request_id":"req-test"}'
        ;;
esac
EOF

chmod +x "$TMP_DIR/bin/curl"

FAL_AI_IMAGE_CONFIG_FILE="$TMP_DIR/.env"
FAL_TEST_LOG_DIR="$TMP_DIR/logs"
PATH="$TMP_DIR/bin:$PATH"
export FAL_AI_IMAGE_CONFIG_FILE FAL_TEST_LOG_DIR PATH

mkdir -p "$FAL_TEST_LOG_DIR"

sh "$SCRIPTS_DIR/edit.sh" \
  --model gpt \
  --prompt "targeted edit" \
  --image-urls "https://example.com/source.png" \
  --mask-url "https://example.com/mask.png" \
  --image-size auto \
  >/dev/null

grep '"mask_url":"https://example.com/mask.png"' "$FAL_TEST_LOG_DIR/payload.json" >/dev/null
grep 'https://queue.fal.run/openai/gpt-image-2/edit' "$FAL_TEST_LOG_DIR/url.txt" >/dev/null
grep 'https://queue.fal.run/openai/gpt-image-2/requests/req-test/status' "$FAL_TEST_LOG_DIR/url.txt" >/dev/null

echo "test_edit_openai_mask: all passed"
