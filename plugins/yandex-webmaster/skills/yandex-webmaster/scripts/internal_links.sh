#!/bin/sh
# Broken internal links — samples and history
# Usage: internal_links.sh --host <domain> --action samples|history
#        [--indicator SITE_ERROR|DISALLOWED_BY_USER|UNSUPPORTED_BY_ROBOT]
#        [--date-from] [--date-to] [--limit N] [--offset N]

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/common.sh"
load_config

INDICATOR=""

_args=""
while [ $# -gt 0 ]; do
    case "$1" in
        --indicator) INDICATOR="$2"; shift 2 ;;
        *)           _args="$_args $1"; shift ;;
    esac
done
# shellcheck disable=SC2086
parse_host_params $_args
ensure_user_id
resolve_host
require_host

ACTION="${ACTION:-samples}"
TMPFILE="${WM_TMPDIR}/wm_intlinks_$$.json"
trap 'rm -f "$TMPFILE"' EXIT

case "$ACTION" in
    samples)
        _curl_args=""
        if [ -n "$LIMIT" ]; then
            _curl_args="--data-urlencode limit=$LIMIT"
        fi
        if [ -n "$OFFSET" ]; then
            _curl_args="$_curl_args --data-urlencode offset=$OFFSET"
        fi
        if [ -n "$INDICATOR" ]; then
            _curl_args="$_curl_args --data-urlencode indicator=$INDICATOR"
        fi

        # shellcheck disable=SC2086
        webmaster_get "/links/internal/broken/samples" $_curl_args > "$TMPFILE"

        _count=$(json_extract_number "$(cat "$TMPFILE")" "count")

        echo "source_url	destination_url	discovery_date"
        tr -d '\n\r' < "$TMPFILE" | sed 's/},{/}\n{/g' | while IFS= read -r _line || [ -n "$_line" ]; do
            _src=$(json_extract_field_raw "$_line" "source_url")
            [ -z "$_src" ] && continue
            _dst=$(json_extract_field_raw "$_line" "destination_url")
            _disc=$(json_extract_field_raw "$_line" "discovery_date")
            printf '%s\t%s\t%s\n' "$_src" "$_dst" "${_disc:--}"
        done | head -30

        echo ""
        echo "Total broken links: ${_count:-?} (showing first 30)"
        ;;

    history)
        _host_dir=$(cache_host_dir)
        mkdir -p "$_host_dir/links"
        _hash=$(cache_key "int_links_history_${DATE_FROM}_${DATE_TO}")
        _out_file="$_host_dir/links/internal_history_${_hash}.tsv"

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
        webmaster_get "/links/internal/broken/history" $_curl_args > "$TMPFILE"

        # Grep from file, not variable
        tr -d '\n\r' < "$TMPFILE" > "${TMPFILE}.flat"
        _tdbu="${WM_TMPDIR}/wm_il_dbu_$$.txt"
        _tse="${WM_TMPDIR}/wm_il_se_$$.txt"
        _tubr="${WM_TMPDIR}/wm_il_ubr_$$.txt"
        trap 'rm -f "$TMPFILE" "${TMPFILE}.flat" "$_tdbu" "$_tse" "$_tubr"' EXIT

        grep -o '"DISALLOWED_BY_USER"[[:space:]]*:\[[^]]*\]' "${TMPFILE}.flat" | head -1 > "$_tdbu"
        grep -o '"SITE_ERROR"[[:space:]]*:\[[^]]*\]' "${TMPFILE}.flat" | head -1 > "$_tse"
        grep -o '"UNSUPPORTED_BY_ROBOT"[[:space:]]*:\[[^]]*\]' "${TMPFILE}.flat" | head -1 > "$_tubr"

        {
            echo "date	site_error	disallowed_by_user	unsupported_by_robot"
            grep -o '"date":"[^"]*","value":[0-9]*' "$_tse" | while IFS= read -r _match; do
                _date=$(printf '%s' "$_match" | sed 's/.*"date":"//;s/".*//' | cut -c1-10)
                _vse=$(printf '%s' "$_match" | sed 's/.*"value"://')
                _vdbu=$(grep -o "\"$_date[^\"]*\",\"value\":[0-9]*" "$_tdbu" | head -1 | sed 's/.*"value"://')
                _vubr=$(grep -o "\"$_date[^\"]*\",\"value\":[0-9]*" "$_tubr" | head -1 | sed 's/.*"value"://')
                printf '%s\t%s\t%s\t%s\n' "$_date" "${_vse:-0}" "${_vdbu:-0}" "${_vubr:-0}"
            done
        } > "$_out_file"

        print_tsv_head "$_out_file" 30
        echo ""
        echo "Cached: $_out_file"
        ;;

    *)
        echo "Error: unknown action '$ACTION'. Use: samples, history" >&2
        exit 1
        ;;
esac
