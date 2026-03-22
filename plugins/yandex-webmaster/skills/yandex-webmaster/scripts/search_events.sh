#!/bin/sh
# Search events — appeared/removed from search
# Usage: search_events.sh --host <domain> --action history|samples
#        [--date-from] [--date-to] [--limit N] [--offset N]

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/common.sh"
load_config

parse_host_params "$@"
ensure_user_id
resolve_host
require_host

ACTION="${ACTION:-history}"
TMPFILE="${WM_TMPDIR}/wm_sevents_$$.json"
trap 'rm -f "$TMPFILE"' EXIT

case "$ACTION" in
    history)
        _curl_args=""
        if [ -n "$DATE_FROM" ]; then
            _curl_args="--data-urlencode date_from=${DATE_FROM}T00:00:00.000+0300"
        fi
        if [ -n "$DATE_TO" ]; then
            _curl_args="$_curl_args --data-urlencode date_to=${DATE_TO}T00:00:00.000+0300"
        fi

        # shellcheck disable=SC2086
        webmaster_get "/search-urls/events/history" $_curl_args > "$TMPFILE"

        _host_dir=$(cache_host_dir)
        mkdir -p "$_host_dir/insearch"
        _hash=$(cache_key "events_history_${DATE_FROM}_${DATE_TO}")
        _out_file="$_host_dir/insearch/events_${_hash}.tsv"

        _body=$(cat "$TMPFILE")
        _appeared=$(printf '%s' "$_body" | grep -o '"APPEARED_IN_SEARCH"[[:space:]]*:\[[^]]*\]' | head -1)
        _removed=$(printf '%s' "$_body" | grep -o '"REMOVED_FROM_SEARCH"[[:space:]]*:\[[^]]*\]' | head -1)

        {
            echo "date	appeared	removed"
            printf '%s' "$_appeared" | grep -o '"date":"[^"]*","value":[0-9]*' | while IFS= read -r _match; do
                _date=$(printf '%s' "$_match" | sed 's/.*"date":"//;s/".*//' | cut -c1-10)
                _app=$(printf '%s' "$_match" | sed 's/.*"value"://')
                _rem=$(printf '%s' "$_removed" | grep -o "\"$_date[^\"]*\",\"value\":[0-9]*" | head -1 | sed 's/.*"value"://')
                printf '%s\t%s\t%s\n' "$_date" "${_app:-0}" "${_rem:-0}"
            done
        } > "$_out_file"

        print_tsv_head "$_out_file" 30
        echo ""
        echo "Cached: $_out_file"
        ;;

    samples)
        _curl_args=""
        if [ -n "$LIMIT" ]; then
            _curl_args="--data-urlencode limit=$LIMIT"
        fi
        if [ -n "$OFFSET" ]; then
            _curl_args="$_curl_args --data-urlencode offset=$OFFSET"
        fi

        # shellcheck disable=SC2086
        webmaster_get "/search-urls/events/samples" $_curl_args > "$TMPFILE"

        _count=$(json_extract_number "$(cat "$TMPFILE")" "count")

        echo "url	title	event	event_date	excluded_status"
        tr -d '\n\r' < "$TMPFILE" | sed 's/},{/}\n{/g' | while IFS= read -r _line || [ -n "$_line" ]; do
            _url=$(json_extract_field_raw "$_line" "url")
            [ -z "$_url" ] && continue
            _title=$(json_extract_field_raw "$_line" "title")
            _event=$(json_extract_field_raw "$_line" "event")
            _edate=$(json_extract_field_raw "$_line" "event_date")
            _exstatus=$(json_extract_field_raw "$_line" "excluded_url_status")
            _ed=$(printf '%s' "$_edate" | cut -c1-10)
            printf '%s\t%s\t%s\t%s\t%s\n' "$_url" "${_title:--}" "$_event" "${_ed:--}" "${_exstatus:--}"
        done | head -30

        echo ""
        echo "Total events: ${_count:-?} (showing first 30, max 50000 via API)"
        ;;

    *)
        echo "Error: unknown action '$ACTION'. Use: history, samples" >&2
        exit 1
        ;;
esac
