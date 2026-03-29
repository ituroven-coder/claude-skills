#!/usr/bin/env bash
# Export channel posts to CSV
# Usage: bash scripts/export_csv.sh --channel <username> [--limit 100] --csv path/to/output.csv

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/common.sh"

load_config
parse_common_params "$@"
require_channel

if [ -z "$CSV_OUT" ]; then
    _cache_dir=$(cache_dir_for_channel "$CHANNEL")
    CSV_OUT="$_cache_dir/${CHANNEL}_export.csv"
fi

_cache_dir=$(cache_dir_for_channel "$CHANNEL")
_posts_file="$_cache_dir/posts.tsv"

# Ensure we have posts
if [ ! -s "$_posts_file" ]; then
    echo "Fetching posts..." >&2
    fetch_channel_pages "$CHANNEL" "$LIMIT" "" "" > "$_posts_file"
fi

# Convert TSV to CSV with proper escaping
{
    echo "id,date,views,reactions,fwd_from,fwd_link,text_preview,media_url,url"
    awk -F'\t' -v ch="$CHANNEL" '{
        gsub(/"/, "\"\"", $7)
        url = "https://t.me/" ch "/" $1
        printf "%s,%s,%s,%s,%s,%s,\"%s\",%s,%s\n", $1, $2, $3, $4, $5, $6, $7, $8, url
    }' "$_posts_file"
} > "$CSV_OUT"

_count=$(wc -l < "$CSV_OUT" | tr -d ' ')
echo "Exported $(( _count - 1 )) posts to: $CSV_OUT"
