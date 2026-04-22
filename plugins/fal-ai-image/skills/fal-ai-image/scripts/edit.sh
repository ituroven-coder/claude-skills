#!/bin/sh
# Edit images via fal.ai using reference images.
# Supports Nano Banana Pro and OpenAI GPT Image 2 (selected via config/.env).

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/common.sh"

PROMPT=""
IMAGE_URLS=""
MODEL_OVERRIDE=""
MASK_URL=""
ASPECT_RATIO="auto"
RESOLUTION="1K"
IMAGE_SIZE=""
QUALITY=""
NUM_IMAGES=1
OUTPUT_FORMAT="png"
OUTPUT_DIR=""
FILENAME="edited"

while [ $# -gt 0 ]; do
    case $1 in
        --prompt|-p) PROMPT="$2"; shift 2 ;;
        --image-urls|-i) IMAGE_URLS="$2"; shift 2 ;;
        --model|-m) MODEL_OVERRIDE="$2"; shift 2 ;;
        --mask-url) MASK_URL="$2"; shift 2 ;;
        --aspect-ratio|-a) ASPECT_RATIO="$2"; shift 2 ;;
        --resolution|-r) RESOLUTION="$2"; shift 2 ;;
        --image-size) IMAGE_SIZE="$2"; shift 2 ;;
        --quality) QUALITY="$2"; shift 2 ;;
        --num-images|-n) NUM_IMAGES="$2"; shift 2 ;;
        --output-format|-f) OUTPUT_FORMAT="$2"; shift 2 ;;
        --output-dir|-o) OUTPUT_DIR="$2"; shift 2 ;;
        --filename) FILENAME="$2"; shift 2 ;;
        *) die "Unknown option: $1" ;;
    esac
done

load_config "$MODEL_OVERRIDE"

[ -n "$PROMPT" ] || die "--prompt is required"
[ -n "$IMAGE_URLS" ] || die "--image-urls is required (comma-separated URLs, max 14)"

IMAGE_URLS_JSON=$(json_array_from_csv "$IMAGE_URLS") || \
    die "Failed to parse --image-urls. Pass a comma-separated list of URLs."
SUBMIT_API_BASE=$(queue_api_base edit)
REQUEST_API_BASE=$(request_api_base)
REFERENCE_IMAGE_COUNT=$(count_csv_items "$IMAGE_URLS")
PROMPT_JSON=$(json_quote "$PROMPT")

case "$FAL_IMAGE_PROVIDER_RESOLVED" in
    google)
        [ -z "$IMAGE_SIZE" ] || die "--image-size is only supported with OpenAI GPT Image 2. Use --aspect-ratio/--resolution for Nano Banana."
        [ -z "$MASK_URL" ] || die "--mask-url is only supported with OpenAI GPT Image 2 edit."
        if [ -n "$QUALITY" ]; then
            echo "Warning: --quality is ignored for Nano Banana." >&2
        fi

        JSON_PAYLOAD="{\"prompt\":$PROMPT_JSON,\"image_urls\":$IMAGE_URLS_JSON,\"num_images\":$NUM_IMAGES,\"aspect_ratio\":\"$ASPECT_RATIO\",\"resolution\":\"$RESOLUTION\",\"output_format\":\"$OUTPUT_FORMAT\"}"
        SETTINGS_LABEL="$ASPECT_RATIO, $RESOLUTION, $OUTPUT_FORMAT"
        ;;
    openai)
        if [ -n "$QUALITY" ]; then
            validate_openai_quality "$QUALITY" || die "Unsupported --quality '$QUALITY'. Use low, medium, or high."
            EFFECTIVE_QUALITY="$QUALITY"
        else
            EFFECTIVE_QUALITY="$FAL_IMAGE_OPENAI_QUALITY_RESOLVED"
        fi

        IMAGE_SIZE_JSON=$(openai_image_size_json "$IMAGE_SIZE" "$ASPECT_RATIO" "$RESOLUTION" "true")
        JSON_PAYLOAD="{\"prompt\":$PROMPT_JSON,\"image_urls\":$IMAGE_URLS_JSON,\"image_size\":$IMAGE_SIZE_JSON,\"quality\":\"$EFFECTIVE_QUALITY\",\"num_images\":$NUM_IMAGES,\"output_format\":\"$OUTPUT_FORMAT\""
        if [ -n "$MASK_URL" ]; then
            MASK_URL_JSON=$(json_quote "$MASK_URL")
            JSON_PAYLOAD="$JSON_PAYLOAD,\"mask_url\":$MASK_URL_JSON"
        fi
        JSON_PAYLOAD="$JSON_PAYLOAD}"
        SETTINGS_LABEL="$IMAGE_SIZE_JSON, $EFFECTIVE_QUALITY, $OUTPUT_FORMAT"
        ;;
    *)
        die "Unsupported resolved provider '$FAL_IMAGE_PROVIDER_RESOLVED'"
        ;;
esac

echo "Submitting edit request..."
echo "Model: $(model_queue_name edit) ($FAL_IMAGE_SELECTION_SOURCE)"
printf "Prompt: %.100s...\n" "$PROMPT"
echo "Reference images: $REFERENCE_IMAGE_COUNT"
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
