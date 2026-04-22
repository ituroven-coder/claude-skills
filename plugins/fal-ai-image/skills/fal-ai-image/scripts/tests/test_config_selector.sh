#!/bin/sh
# Test config selector logic for fal-ai-image.

set -e

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="$(cd "$TESTS_DIR/.." && pwd)"

run_selector() {
    _label="$1"
    _provider="$2"
    _model="$3"
    _quality="$4"
    _cli_model="$5"

    _td="${TMPDIR:-/tmp}/fal_image_test_$$_$(printf '%s' "$_label" | tr ' /+' '___')"
    rm -rf "$_td"
    mkdir -p "$_td"

    {
        echo "FAL_KEY=test-key"
        [ -n "$_provider" ] && echo "FAL_IMAGE_PROVIDER=$_provider"
        [ -n "$_model" ] && echo "FAL_IMAGE_MODEL=$_model"
        [ -n "$_quality" ] && echo "FAL_IMAGE_OPENAI_QUALITY=$_quality"
    } > "$_td/.env"

    _result=$(
        FAL_AI_IMAGE_CONFIG_FILE="$_td/.env"
        export FAL_AI_IMAGE_CONFIG_FILE

        # shellcheck disable=SC1091
        . "$SCRIPTS_DIR/common.sh"

        if ( load_config "$_cli_model" ) >/dev/null 2>&1; then
            load_config "$_cli_model" >/dev/null
            printf 'PROVIDER=%s\nMODEL=%s\nQUALITY=%s\n' \
                "$FAL_IMAGE_PROVIDER_RESOLVED" \
                "$FAL_IMAGE_MODEL_RESOLVED" \
                "$FAL_IMAGE_OPENAI_QUALITY_RESOLVED"
        else
            printf 'DIE\n'
        fi
    )

    rm -rf "$_td"
    printf '%s' "$_result"
}

assert_contains() {
    _label="$1"
    _haystack="$2"
    _needle="$3"

    case "$_haystack" in
        *"$_needle"*)
            echo "  ok: $_label contains $_needle"
            ;;
        *)
            echo "  FAIL: $_label missing $_needle"
            echo "    full output: $_haystack"
            exit 1
            ;;
    esac
}

assert_die() {
    _label="$1"
    _result="$2"

    case "$_result" in
        *DIE*)
            echo "  ok: $_label died as expected"
            ;;
        *)
            echo "  FAIL: $_label expected DIE, got: $_result"
            exit 1
            ;;
    esac
}

out=$(run_selector "default" "" "" "" "")
assert_contains "default selector" "$out" "PROVIDER=google"
assert_contains "default selector" "$out" "MODEL=fal-ai/nano-banana-pro"
assert_contains "default selector" "$out" "QUALITY=medium"

out=$(run_selector "provider_openai" "openai" "" "" "")
assert_contains "provider=openai" "$out" "PROVIDER=openai"
assert_contains "provider=openai" "$out" "MODEL=openai/gpt-image-2"

out=$(run_selector "provider_alias" "gpt" "" "high" "")
assert_contains "provider alias" "$out" "PROVIDER=openai"
assert_contains "provider alias" "$out" "QUALITY=high"

out=$(run_selector "model_wins" "google" "openai/gpt-image-2" "" "")
assert_contains "explicit model wins" "$out" "PROVIDER=openai"
assert_contains "explicit model wins" "$out" "MODEL=openai/gpt-image-2"

out=$(run_selector "cli_override_wins" "google" "" "" "gpt")
assert_contains "cli override wins" "$out" "PROVIDER=openai"
assert_contains "cli override wins" "$out" "MODEL=openai/gpt-image-2"

out=$(run_selector "cli_alias_gemini" "openai" "" "" "gemini")
assert_contains "cli alias gemini" "$out" "PROVIDER=google"
assert_contains "cli alias gemini" "$out" "MODEL=fal-ai/nano-banana-pro"

out=$(run_selector "invalid_provider" "banana-party" "" "" "")
assert_die "invalid provider" "$out"

out=$(run_selector "invalid_quality" "openai" "" "ultra" "")
assert_die "invalid quality" "$out"

out=$(run_selector "invalid_cli_model" "" "" "" "banana-party")
assert_die "invalid cli model" "$out"

echo "test_config_selector: all passed"
