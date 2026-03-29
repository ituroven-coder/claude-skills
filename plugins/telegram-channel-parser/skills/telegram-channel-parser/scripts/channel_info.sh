#!/usr/bin/env bash
# Get channel info (title, description, subscribers)
# Usage: bash scripts/channel_info.sh --channel <username>

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/common.sh"

load_config
parse_common_params "$@"
require_channel

_cache_dir=$(cache_dir_for_channel "$CHANNEL")
_info_file="$_cache_dir/info.json"

# Fetch main page
_html_file="$_cache_dir/raw/page_latest.html"
tg_fetch "${TG_BASE_URL}/${CHANNEL}" > "$_html_file"

if [ ! -s "$_html_file" ]; then
    echo "Error: Could not fetch channel page for @$CHANNEL" >&2
    exit 1
fi

# Parse and save
_info=$(parse_channel_info_from_html "$_html_file")
echo "$_info" > "$_info_file"

echo "Channel: @$CHANNEL"
echo "$_info" | sed 's/[{}]//g;s/,/\n/g' | sed 's/"//g;s/:/: /'
