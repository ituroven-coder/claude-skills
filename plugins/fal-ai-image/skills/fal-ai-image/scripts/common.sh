#!/bin/sh
# Common helpers for fal-ai-image skill.
# POSIX sh compatible — no bashisms.

if [ -z "${FAL_AI_IMAGE_SCRIPT_DIR:-}" ]; then
    FAL_AI_IMAGE_SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
fi
if [ -z "${FAL_AI_IMAGE_SKILL_DIR:-}" ]; then
    FAL_AI_IMAGE_SKILL_DIR="$(cd "$FAL_AI_IMAGE_SCRIPT_DIR/.." && pwd)"
fi
FAL_AI_IMAGE_CONFIG_FILE="${FAL_AI_IMAGE_CONFIG_FILE:-$FAL_AI_IMAGE_SKILL_DIR/config/.env}"

FAL_IMAGE_GOOGLE_MODEL="fal-ai/nano-banana-pro"
FAL_IMAGE_OPENAI_MODEL="openai/gpt-image-2"

FAL_IMAGE_PROVIDER_RESOLVED=""
FAL_IMAGE_MODEL_RESOLVED=""
FAL_IMAGE_SELECTION_SOURCE=""
FAL_IMAGE_OPENAI_QUALITY_RESOLVED=""

die() {
    echo "Error: $1" >&2
    exit 1
}

json_quote() {
    if command -v python3 >/dev/null 2>&1; then
        _jq_value="$1" python3 - <<'PYEOF'
import json
import os
print(json.dumps(os.environ["_jq_value"], ensure_ascii=False))
PYEOF
        return 0
    fi

    printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')"
}

normalize_provider() {
    _provider=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')

    case "$_provider" in
        ""|google|gemini|nano|nano-banana|nano-banana-pro)
            printf 'google\n'
            ;;
        openai|gpt|gpt-image-2)
            printf 'openai\n'
            ;;
        *)
            return 1
            ;;
    esac
}

normalize_model() {
    _model=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')

    case "$_model" in
        fal-ai/nano-banana-pro|fal-ai/nano-banana-pro/edit|nano-banana|nano-banana-pro|nano|google|gemini)
            printf '%s\n' "$FAL_IMAGE_GOOGLE_MODEL"
            ;;
        openai/gpt-image-2|openai/gpt-image-2/edit|gpt|gpt-image-2|openai)
            printf '%s\n' "$FAL_IMAGE_OPENAI_MODEL"
            ;;
        *)
            return 1
            ;;
    esac
}

provider_for_model() {
    case "$1" in
        "$FAL_IMAGE_OPENAI_MODEL")
            printf 'openai\n'
            ;;
        *)
            printf 'google\n'
            ;;
    esac
}

validate_openai_quality() {
    case "$1" in
        low|medium|high)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

load_config() {
    _cli_model_override="${1:-}"

    if [ -f "$FAL_AI_IMAGE_CONFIG_FILE" ]; then
        # shellcheck disable=SC1090
        . "$FAL_AI_IMAGE_CONFIG_FILE"
    fi

    if [ -z "${FAL_KEY:-}" ]; then
        die "FAL_KEY not found. Set it in config/.env or the shell environment."
    fi

    if [ -n "$_cli_model_override" ]; then
        FAL_IMAGE_MODEL_RESOLVED=$(normalize_model "$_cli_model_override") || \
            die "Unsupported --model '$_cli_model_override'. Use nano-banana, google, gemini, gpt, openai, '$FAL_IMAGE_GOOGLE_MODEL', or '$FAL_IMAGE_OPENAI_MODEL'."
        FAL_IMAGE_PROVIDER_RESOLVED=$(provider_for_model "$FAL_IMAGE_MODEL_RESOLVED")
        FAL_IMAGE_SELECTION_SOURCE="cli override"
    elif [ -n "${FAL_IMAGE_MODEL:-}" ]; then
        FAL_IMAGE_MODEL_RESOLVED=$(normalize_model "$FAL_IMAGE_MODEL") || \
            die "Unsupported FAL_IMAGE_MODEL='$FAL_IMAGE_MODEL'. Use '$FAL_IMAGE_GOOGLE_MODEL' or '$FAL_IMAGE_OPENAI_MODEL'."
        FAL_IMAGE_PROVIDER_RESOLVED=$(provider_for_model "$FAL_IMAGE_MODEL_RESOLVED")
        FAL_IMAGE_SELECTION_SOURCE="explicit model"
    elif [ -n "${FAL_IMAGE_PROVIDER:-}" ]; then
        FAL_IMAGE_PROVIDER_RESOLVED=$(normalize_provider "$FAL_IMAGE_PROVIDER") || \
            die "Unsupported FAL_IMAGE_PROVIDER='$FAL_IMAGE_PROVIDER'. Use 'google' or 'openai'."
        case "$FAL_IMAGE_PROVIDER_RESOLVED" in
            google) FAL_IMAGE_MODEL_RESOLVED="$FAL_IMAGE_GOOGLE_MODEL" ;;
            openai) FAL_IMAGE_MODEL_RESOLVED="$FAL_IMAGE_OPENAI_MODEL" ;;
        esac
        FAL_IMAGE_SELECTION_SOURCE="provider alias"
    else
        FAL_IMAGE_PROVIDER_RESOLVED="google"
        FAL_IMAGE_MODEL_RESOLVED="$FAL_IMAGE_GOOGLE_MODEL"
        FAL_IMAGE_SELECTION_SOURCE="backward-compatible default"
    fi

    FAL_IMAGE_OPENAI_QUALITY_RESOLVED="${FAL_IMAGE_OPENAI_QUALITY:-medium}"
    validate_openai_quality "$FAL_IMAGE_OPENAI_QUALITY_RESOLVED" || \
        die "Unsupported FAL_IMAGE_OPENAI_QUALITY='$FAL_IMAGE_OPENAI_QUALITY_RESOLVED'. Use low, medium, or high."

    export FAL_IMAGE_PROVIDER_RESOLVED FAL_IMAGE_MODEL_RESOLVED
    export FAL_IMAGE_SELECTION_SOURCE FAL_IMAGE_OPENAI_QUALITY_RESOLVED
}

model_queue_name() {
    _mode="$1"

    case "$_mode" in
        generate|"")
            printf '%s\n' "$FAL_IMAGE_MODEL_RESOLVED"
            ;;
        edit)
            printf '%s/edit\n' "$FAL_IMAGE_MODEL_RESOLVED"
            ;;
        *)
            die "Unsupported mode '$_mode'"
            ;;
    esac
}

queue_api_base() {
    printf 'https://queue.fal.run/%s\n' "$(model_queue_name "$1")"
}

request_api_base() {
    printf 'https://queue.fal.run/%s\n' "$FAL_IMAGE_MODEL_RESOLVED"
}

json_array_from_csv() {
    if command -v python3 >/dev/null 2>&1; then
        _csv_items="$1" python3 - <<'PYEOF'
import json
import os
import sys

items = [item.strip() for item in os.environ["_csv_items"].split(",") if item.strip()]
if not items:
    sys.exit(1)
print(json.dumps(items, ensure_ascii=False, separators=(",", ":")))
PYEOF
        return 0
    fi

    _csv_items="$1"
    _json="["
    _first="true"
    OLD_IFS=$IFS
    IFS=','
    set -- $_csv_items
    IFS=$OLD_IFS
    for _item in "$@"; do
        _trimmed=$(printf '%s' "$_item" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        [ -n "$_trimmed" ] || continue
        _quoted=$(json_quote "$_trimmed")
        if [ "$_first" = "true" ]; then
            _json="$_json$_quoted"
            _first="false"
        else
            _json="$_json,$_quoted"
        fi
    done
    _json="$_json]"

    if [ "$_json" = "[]" ]; then
        return 1
    fi

    printf '%s\n' "$_json"
}

count_csv_items() {
    if command -v python3 >/dev/null 2>&1; then
        _csv_items="$1" python3 - <<'PYEOF'
import os

items = [item.strip() for item in os.environ["_csv_items"].split(",") if item.strip()]
print(len(items))
PYEOF
        return 0
    fi

    _csv_items="$1"
    _count=0
    OLD_IFS=$IFS
    IFS=','
    set -- $_csv_items
    IFS=$OLD_IFS
    for _item in "$@"; do
        _trimmed=$(printf '%s' "$_item" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        [ -n "$_trimmed" ] || continue
        _count=$((_count + 1))
    done
    printf '%s\n' "$_count"
}

openai_image_size_json() {
    command -v python3 >/dev/null 2>&1 || die "python3 is required for OpenAI image size calculation."

    _size_arg="${1:-}"
    _aspect_ratio="${2:-1:1}"
    _resolution="${3:-1K}"
    _allow_auto="${4:-false}"

    _size_arg="$_size_arg" \
    _aspect_ratio="$_aspect_ratio" \
    _resolution="$_resolution" \
    _allow_auto="$_allow_auto" \
    python3 - <<'PYEOF'
import json
import os
import re
import sys

size_arg = os.environ["_size_arg"].strip()
aspect_ratio = os.environ["_aspect_ratio"].strip()
resolution = os.environ["_resolution"].strip() or "1K"
allow_auto = os.environ["_allow_auto"].strip().lower() == "true"

PRESETS = {
    "square_hd",
    "square",
    "portrait_4_3",
    "portrait_16_9",
    "landscape_4_3",
    "landscape_16_9",
}
MIN_PIXELS = 655_360
MAX_PIXELS = 8_294_400
MAX_EDGE = 3840
RESOLUTION_TO_EDGE = {
    "1K": 1024,
    "2K": 2048,
    "4K": 3840,
}


def fail(message: str) -> None:
    print(f"Error: {message}", file=sys.stderr)
    sys.exit(1)


def validate_dimensions(width: int, height: int) -> None:
    if width % 16 != 0 or height % 16 != 0:
        fail("OpenAI image_size width and height must be multiples of 16.")
    if width > MAX_EDGE or height > MAX_EDGE:
        fail(f"OpenAI image_size max edge is {MAX_EDGE}px.")
    if width * height < MIN_PIXELS or width * height > MAX_PIXELS:
        fail(
            f"OpenAI image_size total pixels must be between {MIN_PIXELS} and {MAX_PIXELS}."
        )
    ratio = max(width / height, height / width)
    if ratio > 3:
        fail("OpenAI image_size aspect ratio must stay within 3:1.")


def best_size_for_ratio(ratio_value: float, target_edge: int):
    best = None
    desired_height = target_edge / ratio_value if ratio_value >= 1 else target_edge
    desired_width = target_edge if ratio_value >= 1 else target_edge * ratio_value

    for width in range(16, MAX_EDGE + 1, 16):
        height = int(round((width / ratio_value) / 16.0) * 16)
        if height < 16 or height > MAX_EDGE:
            continue
        area = width * height
        if area < MIN_PIXELS or area > MAX_PIXELS:
            continue
        score = abs(width - desired_width) + abs(height - desired_height) + abs((width / height) - ratio_value) * 2000
        if best is None or score < best[0]:
            best = (score, width, height)

    for height in range(16, MAX_EDGE + 1, 16):
        width = int(round((height * ratio_value) / 16.0) * 16)
        if width < 16 or width > MAX_EDGE:
            continue
        area = width * height
        if area < MIN_PIXELS or area > MAX_PIXELS:
            continue
        score = abs(width - desired_width) + abs(height - desired_height) + abs((width / height) - ratio_value) * 2000
        if best is None or score < best[0]:
            best = (score, width, height)

    if best is None:
        fail(f"Unable to derive a valid OpenAI image_size for aspect ratio '{aspect_ratio}' and resolution '{resolution}'.")

    return best[1], best[2]


if size_arg:
    if size_arg in PRESETS:
        print(json.dumps(size_arg))
        sys.exit(0)
    if allow_auto and size_arg == "auto":
        print(json.dumps("auto"))
        sys.exit(0)

    match = re.match(r"^(\d+)[xX](\d+)$", size_arg)
    if not match:
        fail("Unsupported --image-size. Use a preset like landscape_4_3 or dimensions like 1536x1024.")

    width = int(match.group(1))
    height = int(match.group(2))
    validate_dimensions(width, height)
    print(json.dumps({"width": width, "height": height}, separators=(",", ":")))
    sys.exit(0)

if allow_auto and aspect_ratio == "auto":
    print(json.dumps("auto"))
    sys.exit(0)

match = re.match(r"^(\d+):(\d+)$", aspect_ratio)
if not match:
    fail("Unsupported aspect ratio for OpenAI model. Use values like 1:1, 4:3, 16:9 or pass --image-size.")

ratio_w = int(match.group(1))
ratio_h = int(match.group(2))
if ratio_w <= 0 or ratio_h <= 0:
    fail("Aspect ratio values must be positive integers.")

if resolution not in RESOLUTION_TO_EDGE:
    fail("Unsupported resolution for OpenAI model. Use 1K, 2K, 4K or pass --image-size.")

ratio_value = ratio_w / ratio_h
target_edge = RESOLUTION_TO_EDGE[resolution]
width, height = best_size_for_ratio(ratio_value, target_edge)
validate_dimensions(width, height)
print(json.dumps({"width": width, "height": height}, separators=(",", ":")))
PYEOF
}

extract_request_id() {
    printf '%s' "$1" | grep -oE '"request_id":[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/'
}

extract_status() {
    printf '%s' "$1" | grep -oE '"status":[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/'
}

submit_queue_request() {
    _api_base="$1"
    _json_payload="$2"

    curl -s -X POST "$_api_base" \
        -H "Authorization: Key $FAL_KEY" \
        -H "Content-Type: application/json" \
        -d "$_json_payload"
}

wait_for_request() {
    _api_base="$1"
    _request_id="$2"
    _max_attempts="${3:-60}"
    _attempt=0

    while [ "$_attempt" -lt "$_max_attempts" ]; do
        _status_response=$(curl -s "$_api_base/requests/$_request_id/status" \
            -H "Authorization: Key $FAL_KEY")
        _status=$(extract_status "$_status_response")

        case "$_status" in
            COMPLETED)
                echo "Generation complete!"
                echo ""
                return 0
                ;;
            FAILED)
                echo "Error: Generation failed" >&2
                echo "$_status_response" >&2
                return 1
                ;;
            IN_PROGRESS|IN_QUEUE|PENDING)
                echo "Status: $_status..."
                sleep 2
                _attempt=$((_attempt + 1))
                ;;
            *)
                echo "Status: ${_status:-UNKNOWN} (retrying)..."
                sleep 2
                _attempt=$((_attempt + 1))
                ;;
        esac
    done

    echo "Error: Timeout waiting for generation" >&2
    return 1
}

fetch_queue_result() {
    _api_base="$1"
    _request_id="$2"

    curl -s "$_api_base/requests/$_request_id" \
        -H "Authorization: Key $FAL_KEY"
}

download_result_images() {
    _result="$1"
    _output_dir="$2"
    _filename="$3"
    _output_format="$4"
    _num_images="$5"

    [ -n "$_output_dir" ] || return 0

    mkdir -p "$_output_dir"
    _timestamp=$(date +%Y%m%d_%H%M%S)
    _urls=$(printf '%s' "$_result" | grep -oE '"url":[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)"$/\1/')
    _index=0

    echo "Downloading images..."
    for _url in $_urls; do
        _suffix=""
        [ "$_num_images" -gt 1 ] && _suffix="_$_index"
        _output_path="$_output_dir/${_filename}_${_timestamp}${_suffix}.${_output_format}"

        if curl -s -o "$_output_path" "$_url"; then
            echo "Saved: $_output_path"
        else
            echo "Warning: Failed to download $_url" >&2
        fi
        _index=$((_index + 1))
    done
    echo ""
}
