#!/bin/sh
# Search queries history (all or single query)
# Usage: queries_history.sh --host <domain> [--query-id <id>]
#        [--device ALL|DESKTOP|MOBILE_AND_TABLET] [--date-from] [--date-to]

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/common.sh"
load_config

QUERY_ID=""
DEVICE="ALL"

_args=""
while [ $# -gt 0 ]; do
    case "$1" in
        --query-id) QUERY_ID="$2"; shift 2 ;;
        --device)   DEVICE="$2"; shift 2 ;;
        *)          _args="$_args $1"; shift ;;
    esac
done
# shellcheck disable=SC2086
parse_host_params $_args
ensure_user_id
resolve_host
require_host

TMPFILE="${WM_TMPDIR}/wm_qhist_$$.json"
trap 'rm -f "$TMPFILE"' EXIT

_curl_args="--data-urlencode query_indicator=TOTAL_SHOWS"
_curl_args="$_curl_args --data-urlencode query_indicator=TOTAL_CLICKS"
_curl_args="$_curl_args --data-urlencode query_indicator=AVG_SHOW_POSITION"
_curl_args="$_curl_args --data-urlencode device_type_indicator=$DEVICE"

if [ -n "$DATE_FROM" ]; then
    _curl_args="$_curl_args --data-urlencode date_from=${DATE_FROM}T00:00:00.000+0300"
fi
if [ -n "$DATE_TO" ]; then
    _curl_args="$_curl_args --data-urlencode date_to=${DATE_TO}T00:00:00.000+0300"
fi

if [ -n "$QUERY_ID" ]; then
    # Single query history
    # shellcheck disable=SC2086
    webmaster_get "/search-queries/${QUERY_ID}/history" $_curl_args > "$TMPFILE"
else
    # All queries aggregate history
    # shellcheck disable=SC2086
    webmaster_get "/search-queries/all/history" $_curl_args > "$TMPFILE"
fi

# Parse indicators timeline
_host_dir=$(cache_host_dir)
mkdir -p "$_host_dir/queries"
_hash=$(cache_key "history_${QUERY_ID}_${DEVICE}_${DATE_FROM}_${DATE_TO}")
_out_file="$_host_dir/queries/history_${_hash}.tsv"

# TTL cache check (24h)
if [ -z "$NO_CACHE" ] && cache_get_ttl "$_out_file" 1440; then
    print_tsv_head "$_out_file" 30
    echo ""
    echo "(cached: $_out_file)"
    exit 0
fi

# Flatten for reliable grep
tr -d '\n\r' < "$TMPFILE" > "${TMPFILE}.flat"

# Extract each indicator into temp file
_ts="${WM_TMPDIR}/wm_qh_shows_$$.txt"
_tc="${WM_TMPDIR}/wm_qh_clicks_$$.txt"
_tp="${WM_TMPDIR}/wm_qh_pos_$$.txt"
trap 'rm -f "$TMPFILE" "${TMPFILE}.flat" "$_ts" "$_tc" "$_tp"' EXIT

grep -o '"TOTAL_SHOWS"[[:space:]]*:\[[^]]*\]' "${TMPFILE}.flat" | head -1 > "$_ts"
grep -o '"TOTAL_CLICKS"[[:space:]]*:\[[^]]*\]' "${TMPFILE}.flat" | head -1 > "$_tc"
grep -o '"AVG_SHOW_POSITION"[[:space:]]*:\[[^]]*\]' "${TMPFILE}.flat" | head -1 > "$_tp"

{
    echo "date	shows	clicks	avg_position"
    grep -o '"date":"[^"]*","value":[0-9.e+-]*' "$_ts" | while IFS= read -r _match; do
        _date=$(printf '%s' "$_match" | sed 's/.*"date":"//;s/".*//' | cut -c1-10)
        _shows=$(printf '%s' "$_match" | sed 's/.*"value"://')
        _clicks=$(grep -o "\"$_date[^\"]*\",\"value\":[0-9.e+-]*" "$_tc" | head -1 | sed 's/.*"value"://')
        _pos=$(grep -o "\"$_date[^\"]*\",\"value\":[0-9.e+-]*" "$_tp" | head -1 | sed 's/.*"value"://')
        printf '%s\t%s\t%s\t%s\n' "$_date" "${_shows:-0}" "${_clicks:-0}" "${_pos:--}"
    done
} > "$_out_file"

print_tsv_head "$_out_file" 30
echo ""
echo "Cached: $_out_file"
