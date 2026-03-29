#!/usr/bin/env bash
# Fetch posts from a public Telegram channel
# Usage: bash scripts/fetch_posts.sh --channel <username> [--limit 50] [--before <id>] [--after-date YYYY-MM-DD] [--csv path]

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/common.sh"

load_config
parse_common_params "$@"
require_channel

_cache_dir=$(cache_dir_for_channel "$CHANNEL")
_posts_file="$_cache_dir/posts.tsv"

# Header for output
echo "id	date	views	forwards	reactions	text_preview"

# Fetch with pagination
_result=$(fetch_channel_pages "$CHANNEL" "$LIMIT" "$BEFORE" "$AFTER_DATE")

if [ -z "$_result" ]; then
    echo "(no posts found)" >&2
    exit 0
fi

# Save to cache
echo "$_result" > "$_posts_file"

# Export to CSV if requested
if [ -n "$CSV_OUT" ]; then
    {
        echo "id,date,views,forwards,reactions,text_preview"
        echo "$_result" | awk -F'\t' '{
            gsub(/"/, "\"\"", $6)
            printf "%s,%s,%s,%s,%s,\"%s\"\n", $1, $2, $3, $4, $5, $6
        }'
    } > "$CSV_OUT"
    echo "Exported to: $CSV_OUT" >&2
fi

# Output with limit
_count=$(echo "$_result" | wc -l | tr -d ' ')
if [ "$_count" -gt 30 ]; then
    echo "$_result" | head -30
    echo "... ($((  _count - 30 )) more rows, full data in: $_posts_file)"
else
    echo "$_result"
fi
