#!/usr/bin/env bash
# Top posts by views, forwards, or reactions (шер-парад)
# Usage: bash scripts/top_posts.sh --channel <username> [--limit 50] [--sort views|forwards|reactions]

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/common.sh"

load_config
parse_common_params "$@"
require_channel

_cache_dir=$(cache_dir_for_channel "$CHANNEL")
_posts_file="$_cache_dir/posts.tsv"

# Ensure we have posts
if [ ! -s "$_posts_file" ]; then
    echo "Fetching posts..." >&2
    fetch_channel_pages "$CHANNEL" "$LIMIT" "" "" > "$_posts_file"
fi

# Determine sort column: 3=views, 4=forwards, 5=reactions
case "$SORT_BY" in
    views|view)       _sort_col=3 ;;
    forwards|forward|fwd|shares|share) _sort_col=4 ;;
    reactions|reaction|react)          _sort_col=5 ;;
    *)                _sort_col=3 ;;
esac

echo "=== Top posts by $SORT_BY for @$CHANNEL ==="
echo "rank	id	date	views	forwards	reactions	text_preview"

# Normalize K/M values and sort numerically descending
awk -F'\t' -v col="$_sort_col" '
{
    val = $col
    gsub(/[[:space:]]/, "", val)
    multiplier = 1
    if (val ~ /[Kk]$/) { sub(/[Kk]$/, "", val); multiplier = 1000 }
    if (val ~ /[Mm]$/) { sub(/[Mm]$/, "", val); multiplier = 1000000 }
    # Handle decimal
    if (val ~ /\./) {
        norm = val * multiplier
    } else {
        norm = val * multiplier
    }
    if (norm == "" || norm == 0) norm = 0
    printf "%d\t%s\n", norm, $0
}
' "$_posts_file" | sort -t'	' -k1 -nr | head -n "${LIMIT:-20}" | awk -F'\t' '
{
    # Remove the prepended sort key, add rank
    printf "%d\t", NR
    for (i = 2; i <= NF; i++) {
        printf "%s%s", $i, (i < NF ? "\t" : "\n")
    }
}
'

# Engagement summary
echo "" >&2
echo "--- Engagement summary ---" >&2
awk -F'\t' '
{
    gsub(/[[:space:]]/, "", $3)
    gsub(/[[:space:]]/, "", $4)
    v = $3; f = $4
    # Normalize
    if (v ~ /[Kk]$/) { sub(/[Kk]$/, "", v); v = v * 1000 }
    if (v ~ /[Mm]$/) { sub(/[Mm]$/, "", v); v = v * 1000000 }
    if (f ~ /[Kk]$/) { sub(/[Kk]$/, "", f); f = f * 1000 }
    if (f ~ /[Mm]$/) { sub(/[Mm]$/, "", f); f = f * 1000000 }
    total_views += v
    total_fwds += f
    n++
}
END {
    if (n > 0) {
        printf "Posts: %d | Avg views: %d | Avg forwards: %d", n, total_views/n, total_fwds/n
        if (total_views > 0) printf " | Share rate: %.1f%%", (total_fwds/total_views)*100
        printf "\n"
    }
}
' "$_posts_file" >&2
