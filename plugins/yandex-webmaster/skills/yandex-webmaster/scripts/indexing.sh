#!/bin/sh
# Indexing history and samples
# Usage: indexing.sh --host <domain> --action history|samples
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
TMPFILE="${WM_TMPDIR}/wm_indexing_$$.json"
trap 'rm -f "$TMPFILE"' EXIT

case "$ACTION" in
    history)
        _host_dir=$(cache_host_dir)
        mkdir -p "$_host_dir/indexing"
        _hash=$(cache_key "indexing_history_${DATE_FROM}_${DATE_TO}")
        _out_file="$_host_dir/indexing/history_${_hash}.tsv"

        # TTL cache check (24h)
        if [ -z "$NO_CACHE" ] && cache_get_ttl "$_out_file" 1440; then
            print_tsv_head "$_out_file" 30
            echo ""
            echo "(cached: $_out_file)"
            exit 0
        fi

        _curl_args=""
        if [ -n "$DATE_FROM" ]; then
            _curl_args="--data-urlencode date_from=${DATE_FROM}T00:00:00.000+0300"
        fi
        if [ -n "$DATE_TO" ]; then
            _curl_args="$_curl_args --data-urlencode date_to=${DATE_TO}T00:00:00.000+0300"
        fi

        # shellcheck disable=SC2086
        webmaster_get "/indexing/history" $_curl_args > "$TMPFILE"

        # Flatten JSON to one line for reliable grep
        tr -d '\n\r' < "$TMPFILE" > "${TMPFILE}.flat"

        # Extract each indicator array into its own temp file
        _t2="${WM_TMPDIR}/wm_idx_2xx_$$.txt"
        _t3="${WM_TMPDIR}/wm_idx_3xx_$$.txt"
        _t4="${WM_TMPDIR}/wm_idx_4xx_$$.txt"
        _t5="${WM_TMPDIR}/wm_idx_5xx_$$.txt"
        _to="${WM_TMPDIR}/wm_idx_oth_$$.txt"
        trap 'rm -f "$TMPFILE" "${TMPFILE}.flat" "$_t2" "$_t3" "$_t4" "$_t5" "$_to"' EXIT

        grep -o '"HTTP_2XX"[[:space:]]*:\[[^]]*\]' "${TMPFILE}.flat" | head -1 > "$_t2"
        grep -o '"HTTP_3XX"[[:space:]]*:\[[^]]*\]' "${TMPFILE}.flat" | head -1 > "$_t3"
        grep -o '"HTTP_4XX"[[:space:]]*:\[[^]]*\]' "${TMPFILE}.flat" | head -1 > "$_t4"
        grep -o '"HTTP_5XX"[[:space:]]*:\[[^]]*\]' "${TMPFILE}.flat" | head -1 > "$_t5"
        grep -o '"OTHER"[[:space:]]*:\[[^]]*\]' "${TMPFILE}.flat" | head -1 > "$_to"

        {
            echo "date	2xx	3xx	4xx	5xx	other"
            grep -o '"date":"[^"]*","value":[0-9]*' "$_t2" | while IFS= read -r _match; do
                _date=$(printf '%s' "$_match" | sed 's/.*"date":"//;s/".*//' | cut -c1-10)
                _v2=$(printf '%s' "$_match" | sed 's/.*"value"://')
                _v3=$(grep -o "\"$_date[^\"]*\",\"value\":[0-9]*" "$_t3" | head -1 | sed 's/.*"value"://')
                _v4=$(grep -o "\"$_date[^\"]*\",\"value\":[0-9]*" "$_t4" | head -1 | sed 's/.*"value"://')
                _v5=$(grep -o "\"$_date[^\"]*\",\"value\":[0-9]*" "$_t5" | head -1 | sed 's/.*"value"://')
                _vo=$(grep -o "\"$_date[^\"]*\",\"value\":[0-9]*" "$_to" | head -1 | sed 's/.*"value"://')
                printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$_date" "${_v2:-0}" "${_v3:-0}" "${_v4:-0}" "${_v5:-0}" "${_vo:-0}"
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
        webmaster_get "/indexing/samples" $_curl_args > "$TMPFILE"

        _count=$(json_extract_number "$(cat "$TMPFILE")" "count")

        echo "url	status	http_code	access_date"
        tr -d '\n\r' < "$TMPFILE" | sed 's/},{/}\n{/g' | while IFS= read -r _line || [ -n "$_line" ]; do
            _url=$(json_extract_field_raw "$_line" "url")
            [ -z "$_url" ] && continue
            _status=$(json_extract_field_raw "$_line" "status")
            _code=$(json_extract_number "$_line" "http_code")
            _access=$(json_extract_field_raw "$_line" "access_date")
            _adate=$(printf '%s' "$_access" | cut -c1-10)
            printf '%s\t%s\t%s\t%s\n' "$_url" "$_status" "${_code:--}" "${_adate:--}"
        done | head -30

        echo ""
        echo "Total URLs: ${_count:-?} (showing first 30, max 50000 via API)"
        ;;

    *)
        echo "Error: unknown action '$ACTION'. Use: history, samples" >&2
        exit 1
        ;;
esac
