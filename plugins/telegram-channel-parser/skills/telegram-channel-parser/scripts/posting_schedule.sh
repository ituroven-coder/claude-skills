#!/usr/bin/env bash
# Analyze posting schedule: frequency, best hours, day-of-week distribution
# Usage: bash scripts/posting_schedule.sh --channel <username> [--limit 100]

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

echo "=== Posting schedule for @$CHANNEL ==="
echo ""

# Extract hours and day-of-week from ISO dates
echo "--- Posts by hour (UTC) ---"
awk -F'\t' '
{
    # Date format: 2026-03-28T12:40:00+00:00 or similar
    split($2, dt, "T")
    if (length(dt) >= 2) {
        split(dt[2], tm, ":")
        hour = tm[1] + 0
        hours[hour]++
        total++
    }
}
END {
    for (h = 0; h < 24; h++) {
        count = (h in hours) ? hours[h] : 0
        bar = ""
        for (i = 0; i < count; i++) bar = bar "█"
        printf "%02d:00  %3d  %s\n", h, count, bar
    }
    printf "\nTotal posts analyzed: %d\n", total
}
' "$_posts_file"

echo ""
echo "--- Posts by day of week ---"
awk -F'\t' '
{
    split($2, dt, "T")
    # Use date command to get day of week
    cmd = "date -d \"" dt[1] "\" +%u 2>/dev/null || date -j -f %Y-%m-%d \"" dt[1] "\" +%u 2>/dev/null"
    cmd | getline dow
    close(cmd)
    if (dow != "") days[dow]++
}
END {
    names[1] = "Mon"; names[2] = "Tue"; names[3] = "Wed"
    names[4] = "Thu"; names[5] = "Fri"; names[6] = "Sat"; names[7] = "Sun"
    for (d = 1; d <= 7; d++) {
        count = (d in days) ? days[d] : 0
        bar = ""
        for (i = 0; i < count; i++) bar = bar "█"
        printf "%s  %3d  %s\n", names[d], count, bar
    }
}
' "$_posts_file"

echo ""
echo "--- Posting frequency ---"
awk -F'\t' '
{
    split($2, dt, "T")
    dates[dt[1]]++
    n++
}
END {
    # Count unique dates
    for (d in dates) days_count++
    if (days_count > 1) {
        # Find date range
        min_d = "9999-99-99"; max_d = "0000-00-00"
        for (d in dates) {
            if (d < min_d) min_d = d
            if (d > max_d) max_d = d
        }
        printf "Period: %s to %s\n", min_d, max_d
        printf "Posts: %d over %d unique days\n", n, days_count
        printf "Avg: %.1f posts/day (on active days)\n", n / days_count
    }
}
' "$_posts_file"
