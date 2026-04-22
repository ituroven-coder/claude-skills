#!/bin/sh
# Generate images via fal.ai.
# Supports Nano Banana Pro and OpenAI GPT Image 2 (selected via config/.env).

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/common.sh"

PROMPT=""
MODEL_OVERRIDE=""
ASPECT_RATIO="1:1"
RESOLUTION="1K"
IMAGE_SIZE=""
QUALITY=""
NUM_IMAGES=1
OUTPUT_FORMAT="png"
OUTPUT_DIR=""
FILENAME="generated"
WEB_SEARCH="false"

while [ $# -gt 0 ]; do
    case $1 in
        --prompt|-p) PROMPT="$2"; shift 2 ;;
        --model|-m) MODEL_OVERRIDE="$2"; shift 2 ;;
        --aspect-ratio|-a) ASPECT_RATIO="$2"; shift 2 ;;
        --resolution|-r) RESOLUTION="$2"; shift 2 ;;
        --image-size) IMAGE_SIZE="$2"; shift 2 ;;
        --quality) QUALITY="$2"; shift 2 ;;
        --num-images|-n) NUM_IMAGES="$2"; shift 2 ;;
        --output-format|-f) OUTPUT_FORMAT="$2"; shift 2 ;;
        --output-dir|-o) OUTPUT_DIR="$2"; shift 2 ;;
        --filename) FILENAME="$2"; shift 2 ;;
        --web-search|-w) WEB_SEARCH="true"; shift ;;
        *) die "Unknown option: $1" ;;
    esac
done

load_config "$MODEL_OVERRIDE"

[ -n "$PROMPT" ] || die "--prompt is required"

SUBMIT_API_BASE=$(queue_api_base generate)
REQUEST_API_BASE=$(request_api_base)
PROMPT_JSON=$(json_quote "$PROMPT")

case "$FAL_IMAGE_PROVIDER_RESOLVED" in
    google)
        [ -z "$IMAGE_SIZE" ] || die "--image-size is only supported with OpenAI GPT Image 2. Use --aspect-ratio/--resolution for Nano Banana."
        if [ -n "$QUALITY" ]; then
            echo "Warning: --quality is ignored for Nano Banana." >&2
        fi

        JSON_PAYLOAD="{\"prompt\":$PROMPT_JSON,\"num_images\":$NUM_IMAGES,\"aspect_ratio\":\"$ASPECT_RATIO\",\"resolution\":\"$RESOLUTION\",\"output_format\":\"$OUTPUT_FORMAT\""
        if [ "$WEB_SEARCH" = "true" ]; then
            JSON_PAYLOAD="$JSON_PAYLOAD,\"enable_web_search\":true"
        fi
        JSON_PAYLOAD="$JSON_PAYLOAD}"
        SETTINGS_LABEL="$ASPECT_RATIO, $RESOLUTION, $OUTPUT_FORMAT"
        ;;
    openai)
        if [ "$WEB_SEARCH" = "true" ]; then
            echo "Warning: --web-search is not supported by openai/gpt-image-2 and will be ignored." >&2
        fi

        if [ -n "$QUALITY" ]; then
            validate_openai_quality "$QUALITY" || die "Unsupported --quality '$QUALITY'. Use low, medium, or high."
            EFFECTIVE_QUALITY="$QUALITY"
        else
            EFFECTIVE_QUALITY="$FAL_IMAGE_OPENAI_QUALITY_RESOLVED"
        fi

        IMAGE_SIZE_JSON=$(openai_image_size_json "$IMAGE_SIZE" "$ASPECT_RATIO" "$RESOLUTION" "false")
        JSON_PAYLOAD="{\"prompt\":$PROMPT_JSON,\"image_size\":$IMAGE_SIZE_JSON,\"quality\":\"$EFFECTIVE_QUALITY\",\"num_images\":$NUM_IMAGES,\"output_format\":\"$OUTPUT_FORMAT\"}"
        SETTINGS_LABEL="$IMAGE_SIZE_JSON, $EFFECTIVE_QUALITY, $OUTPUT_FORMAT"
        ;;
    *)
        die "Unsupported resolved provider '$FAL_IMAGE_PROVIDER_RESOLVED'"
        ;;
esac

echo "Submitting request..."
echo "Model: $FAL_IMAGE_MODEL_RESOLVED ($FAL_IMAGE_SELECTION_SOURCE)"
printf "Prompt: %.100s...\n" "$PROMPT"
echo "Settings: $SETTINGS_LABEL"
echo ""

SUBMIT_RESPONSE=$(submit_queue_request "$SUBMIT_API_BASE" "$JSON_PAYLOAD")
REQUEST_ID=$(extract_request_id "$SUBMIT_RESPONSE")

[ -n "$REQUEST_ID" ] || {
    echo "Error: Failed to submit request" >&2
    echo "$SUBMIT_RESPONSE" >&2
    exit 1
}

echo "Request ID: $REQUEST_ID"
echo "Waiting for generation..."

wait_for_request "$REQUEST_API_BASE" "$REQUEST_ID"
RESULT=$(fetch_queue_result "$REQUEST_API_BASE" "$REQUEST_ID")

download_result_images "$RESULT" "$OUTPUT_DIR" "$FILENAME" "$OUTPUT_FORMAT" "$NUM_IMAGES"

echo "=== RESULT JSON ==="
printf '%s\n' "$RESULT"
echo "=== END RESULT ==="
echo ""
echo "Note: URLs expire in ~1 hour"
