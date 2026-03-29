#!/usr/bin/env bash
# Digest: collect fresh posts from multiple channels for a time period
# Usage: bash scripts/digest.sh --channels "ch1,ch2,ch3" --period today
# Or:    bash scripts/digest.sh --period yesterday  (uses TG_CHANNELS from config)

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/common.sh"

load_config
parse_common_params "$@"
require_channels

# Default period
if [ -z "$PERIOD" ]; then
    PERIOD="today"
fi

# Convert period to after_date
_after_date=$(period_to_after_date "$PERIOD")
if [ -z "$_after_date" ]; then
    echo "Error: invalid --period '$PERIOD'. Use: today, yesterday, week, or N (days)." >&2
    exit 1
fi

echo "=== Telegram Digest: $PERIOD (since $_after_date) ==="
echo ""

# Process each channel
_old_ifs="$IFS"
IFS=','
for _channel in $CHANNELS; do
    # Trim whitespace
    _channel=$(echo "$_channel" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    if [ -z "$_channel" ]; then
        continue
    fi

    echo "--- @$_channel ---"

    # Fetch posts with date filter
    _cache_dir=$(cache_dir_for_channel "$_channel")
    _digest_file="$_cache_dir/digest_${PERIOD}.tsv"

    _result=$(fetch_channel_pages "$_channel" "50" "" "$_after_date" 2>/dev/null) || true

    if [ -z "$_result" ]; then
        echo "(no posts for this period)"
        echo ""
        continue
    fi

    echo "$_result" > "$_digest_file"

    _count=$(echo "$_result" | wc -l | tr -d ' ')
    echo "Posts: $_count"
    echo ""

    # Show each post: date | views | text preview
    echo "$_result" | awk -F'\t' '{
        # Extract time from ISO date
        split($2, dt, "T")
        time = dt[2]
        sub(/\+.*/, "", time)
        sub(/:00$/, "", time)

        # Truncate text to 120 chars for digest
        text = $6
        if (length(text) > 120) text = substr(text, 1, 120) "..."

        printf "  %s | %s views | %s\n", time, $3, text
    }'
    echo ""
done
IFS="$_old_ifs"

echo "=== End of digest ==="
