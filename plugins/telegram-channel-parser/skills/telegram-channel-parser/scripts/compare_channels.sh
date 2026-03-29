#!/usr/bin/env bash
# Compare multiple channels: subscribers, avg views, posting frequency, engagement
# Usage: bash scripts/compare_channels.sh --channels "ch1,ch2,ch3" [--limit 30]

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/common.sh"

load_config
parse_common_params "$@"
require_channels

echo "=== Channel Comparison ==="
echo ""
printf "%-25s %12s %10s %10s %10s %8s\n" "Channel" "Subscribers" "Avg Views" "Avg Fwds" "Share%" "Posts"
printf "%-25s %12s %10s %10s %10s %8s\n" "-------" "-----------" "---------" "--------" "------" "-----"

_old_ifs="$IFS"
IFS=','
for _channel in $CHANNELS; do
    _channel=$(echo "$_channel" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [ -z "$_channel" ] && continue

    _cache_dir=$(cache_dir_for_channel "$_channel")

    # Fetch info
    _html_file="$_cache_dir/raw/page_latest.html"
    tg_fetch "${TG_BASE_URL}/${_channel}" > "$_html_file" 2>/dev/null || true

    _subs=""
    if [ -s "$_html_file" ]; then
        _info=$(parse_channel_info_from_html "$_html_file")
        _subs=$(echo "$_info" | grep -o '"subscribers":"[^"]*"' | sed 's/.*"subscribers":"//;s/"//')
    fi

    # Fetch posts
    _posts_file="$_cache_dir/posts.tsv"
    fetch_channel_pages "$_channel" "$LIMIT" "" "" > "$_posts_file" 2>/dev/null || true

    if [ ! -s "$_posts_file" ]; then
        printf "%-25s %12s %10s %10s %10s %8s\n" "@$_channel" "${_subs:-?}" "?" "?" "?" "0"
        continue
    fi

    # Calculate metrics
    _metrics=$(awk -F'\t' '
    {
        v = $3; f = $4
        gsub(/[[:space:]]/, "", v)
        gsub(/[[:space:]]/, "", f)
        # Normalize K/M
        if (v ~ /[Kk]$/) { sub(/[Kk]$/, "", v); v = v * 1000 }
        if (v ~ /[Mm]$/) { sub(/[Mm]$/, "", v); v = v * 1000000 }
        if (f ~ /[Kk]$/) { sub(/[Kk]$/, "", f); f = f * 1000 }
        if (f ~ /[Mm]$/) { sub(/[Mm]$/, "", f); f = f * 1000000 }
        if (v + 0 > 0) total_v += v
        if (f + 0 > 0) total_f += f
        n++
    }
    END {
        avg_v = (n > 0) ? int(total_v / n) : 0
        avg_f = (n > 0) ? int(total_f / n) : 0
        share = (total_v > 0) ? (total_f / total_v) * 100 : 0
        printf "%d\t%d\t%.1f\t%d", avg_v, avg_f, share, n
    }
    ' "$_posts_file")

    _avg_v=$(echo "$_metrics" | cut -f1)
    _avg_f=$(echo "$_metrics" | cut -f2)
    _share=$(echo "$_metrics" | cut -f3)
    _post_count=$(echo "$_metrics" | cut -f4)

    printf "%-25s %12s %10s %10s %9s%% %8s\n" \
        "@$_channel" "${_subs:-?}" "$_avg_v" "$_avg_f" "$_share" "$_post_count"
done
IFS="$_old_ifs"

echo ""
echo "(based on last $LIMIT posts per channel)"
