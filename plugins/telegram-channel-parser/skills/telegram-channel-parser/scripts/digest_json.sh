#!/usr/bin/env bash
# Digest as JSON — ready to inject into React artifact
# Usage: bash scripts/digest_json.sh --period today [--channels "ch1,ch2"]
# Output: JSON with { posts: [...], channels: {...} }

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/common.sh"

load_config
parse_common_params "$@"
require_channels

if [ -z "$PERIOD" ]; then
    PERIOD="today"
fi

_after_date=$(period_to_after_date "$PERIOD")
if [ -z "$_after_date" ]; then
    echo "Error: invalid --period '$PERIOD'." >&2
    exit 1
fi

# Collect all posts and channel info as JSON
_all_posts=""
_all_channels=""

_old_ifs="$IFS"
IFS=','
for _channel in $CHANNELS; do
    _channel=$(echo "$_channel" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [ -z "$_channel" ] && continue

    _cache_dir=$(cache_dir_for_channel "$_channel")
    _html_file="$_cache_dir/raw/page_latest.html"

    # Fetch page (used for both posts and channel info)
    tg_fetch "${TG_BASE_URL}/${_channel}" > "$_html_file" 2>/dev/null || true

    # Channel info
    if [ -s "$_html_file" ]; then
        _info=$(parse_channel_info_from_html "$_html_file")
        _title=$(echo "$_info" | sed 's/.*"title":"//;s/".*//')
        _subs=$(echo "$_info" | sed 's/.*"subscribers":"//;s/".*//')
        if [ -n "$_all_channels" ]; then _all_channels="${_all_channels},"; fi
        _all_channels="${_all_channels}\"${_channel}\":{\"title\":\"${_title}\",\"subscribers\":\"${_subs}\"}"
    fi

    # Posts
    _result=$(fetch_channel_pages "$_channel" "50" "" "$_after_date" 2>/dev/null) || true
    [ -z "$_result" ] && continue

    # Convert TSV to JSON objects
    # TSV: $1=id $2=date $3=views $4=reactions $5=fwd_from $6=fwd_link $7=text $8=media_url
    _posts_json=$(echo "$_result" | awk -F'\t' -v ch="$_channel" '
    {
        id = $1; date = $2; views = $3; reactions = $4
        fwd_from = $5; fwd_link = $6; text = $7; media = $8

        # Escape for JSON: backslashes first, then quotes, then control chars
        gsub(/\\/, "\\\\", text)
        gsub(/"/, "\\\"", text)
        gsub(/\t/, " ", text)
        gsub(/\r/, "", text)

        gsub(/\\/, "\\\\", fwd_from)
        gsub(/"/, "\\\"", fwd_from)

        printf "{\"id\":\"%s\",\"channel\":\"%s\",\"date\":\"%s\",\"views\":\"%s\",\"reactions\":\"%s\"", id, ch, date, views, reactions

        if (fwd_from != "") printf ",\"fwd_from\":\"%s\"", fwd_from
        if (fwd_link != "") printf ",\"fwd_link\":\"%s\"", fwd_link
        if (media != "") printf ",\"mediaUrl\":\"%s\"", media

        printf ",\"text\":\"%s\"}\n", text
    }')

    if [ -n "$_posts_json" ]; then
        # Join with commas
        _comma_posts=$(echo "$_posts_json" | paste -sd ',' -)
        if [ -n "$_all_posts" ]; then _all_posts="${_all_posts},"; fi
        _all_posts="${_all_posts}${_comma_posts}"
    fi
done
IFS="$_old_ifs"

# Output final JSON
printf '{"posts":[%s],"channels":{%s}}\n' "$_all_posts" "$_all_channels"
