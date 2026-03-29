#!/usr/bin/env bash
# Search posts by text query
# Usage: bash scripts/search_posts.sh --channel <username> --query "text" [--limit 50]

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/common.sh"

load_config
parse_common_params "$@"
require_channel

if [ -z "$QUERY" ]; then
    echo "Error: --query \"text\" is required." >&2
    exit 1
fi

_cache_dir=$(cache_dir_for_channel "$CHANNEL")
_posts_file="$_cache_dir/posts.tsv"

# Ensure we have posts cached
if [ ! -s "$_posts_file" ]; then
    echo "Fetching posts first..." >&2
    fetch_channel_pages "$CHANNEL" "$LIMIT" "" "" > "$_posts_file"
fi

echo "id	date	views	reactions	fwd_from	fwd_link	text	media_url"

# Case-insensitive grep
_result=$(grep -i "$QUERY" "$_posts_file" 2>/dev/null || true)

if [ -z "$_result" ]; then
    echo "(no posts matching '$QUERY')" >&2
    exit 0
fi

_count=$(echo "$_result" | wc -l | tr -d ' ')
if [ "$_count" -gt 30 ]; then
    echo "$_result" | head -30
    echo "... ($(( _count - 30 )) more results)"
else
    echo "$_result"
fi

echo "" >&2
echo "Found $_count posts matching '$QUERY' in @$CHANNEL" >&2
