#!/bin/bash
# Get top search phrases from Yandex Wordstat
# Supports --limit (up to 2000) and --csv export

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Defaults
PHRASE=""
REGIONS=""
DEVICES="all"
LIMIT=""
CSV_FILE=""
CSV_SEP=";"
STDOUT_MAX=20

# Parse args
while [[ $# -gt 0 ]]; do
    case $1 in
        --phrase|-p) PHRASE="$2"; shift 2 ;;
        --regions|-r) REGIONS="$2"; shift 2 ;;
        --devices|-d) DEVICES="$2"; shift 2 ;;
        --limit|-l) LIMIT="$2"; shift 2 ;;
        --csv|-c) CSV_FILE="$2"; shift 2 ;;
        --sep) CSV_SEP="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [[ -z "$PHRASE" ]]; then
    echo "Usage: top_requests.sh --phrase \"search query\" [options]"
    echo ""
    echo "Options:"
    echo "  --phrase, -p   Search phrase (required)"
    echo "  --regions, -r  Region IDs, comma-separated (optional)"
    echo "  --devices, -d  Device filter: all, desktop, phone, tablet (default: all)"
    echo "  --limit, -l    Number of results: 1-2000 (API default: 50)"
    echo "  --csv, -c      Export to CSV file (UTF-8 with BOM, semicolon-separated)"
    echo "  --sep          CSV separator (default: ;)"
    echo ""
    echo "Examples:"
    echo "  bash scripts/top_requests.sh --phrase \"юрист по дтп\""
    echo "  bash scripts/top_requests.sh --phrase \"юрист дтп\" --limit 500"
    echo "  bash scripts/top_requests.sh --phrase \"юрист дтп\" --limit 2000 --csv report.csv"
    echo "  bash scripts/top_requests.sh --phrase \"юрист дтп\" --csv report.csv --sep \",\""
    exit 1
fi

# Validate --limit
if [[ -n "$LIMIT" ]]; then
    if ! echo "$LIMIT" | grep -qE '^[0-9]+$'; then
        echo "Error: --limit must be a positive integer (1-2000)"
        exit 1
    fi
    if [[ "$LIMIT" -lt 1 || "$LIMIT" -gt 2000 ]]; then
        echo "Error: --limit must be between 1 and 2000 (got: $LIMIT)"
        exit 1
    fi
fi

load_config

# Escape phrase for JSON
PHRASE_ESCAPED=$(json_escape "$PHRASE")

# Build JSON params
PARAMS="{\"phrase\":\"$PHRASE_ESCAPED\""

if [[ -n "$LIMIT" ]]; then
    PARAMS="$PARAMS,\"numPhrases\":$LIMIT"
fi

if [[ -n "$REGIONS" ]]; then
    PARAMS="$PARAMS,\"regions\":[$REGIONS]"
fi

if [[ "$DEVICES" != "all" ]]; then
    PARAMS="$PARAMS,\"devices\":\"$DEVICES\""
fi

PARAMS="$PARAMS}"

echo "=== Yandex Wordstat: Top Requests ==="
echo "Phrase: $PHRASE"
[[ -n "$REGIONS" ]] && echo "Regions: $REGIONS"
echo "Devices: $DEVICES"
[[ -n "$LIMIT" ]] && echo "Limit: $LIMIT"
[[ -n "$CSV_FILE" ]] && echo "Export: $CSV_FILE (sep='$CSV_SEP')"
echo ""
echo "Fetching data..."

result=$(wordstat_request "topRequests" "$PARAMS")

# Check for error
if echo "$result" | grep -q '"error"'; then
    echo "Error:"
    echo "$result"
    exit 1
fi

# --- CSV helper ---
csv_escape() {
    local val="$1"
    val=$(printf '%s' "$val" | tr -d '\n\r')
    val="${val//\"/\"\"}"
    printf '"%s"' "$val"
}

# --- Init CSV file ---
if [[ -n "$CSV_FILE" ]]; then
    printf '\xEF\xBB\xBF' > "$CSV_FILE"
    printf 'n%sphrase%simpressions%stype\n' "$CSV_SEP" "$CSV_SEP" "$CSV_SEP" >> "$CSV_FILE"
fi

# --- Normalize JSON to single line for safe parsing ---
result=$(printf '%s' "$result" | tr -d '\n\r')

# --- Extract totalCount ---
total_count=$(echo "$result" | grep -o '"totalCount":[0-9]*' | head -1 | sed 's/"totalCount"://')

echo ""
echo "=== Top Requests ==="
if [[ -n "$total_count" ]]; then
    echo "Total count (broad match): $(format_number "$total_count")"
fi
echo ""
echo "| # | Phrase | Impressions |"
echo "|---|--------|-------------|"

# --- Process a JSON array of {phrase, count} entries ---
# Args: $1=entries_string $2=type_label
# Writes to stdout (limited when CSV) and CSV file
process_entries() {
    local entries_str="$1"
    local type_label="$2"
    local rank=0
    local total=0

    # Count total entries for truncation message
    total=$(echo "$entries_str" | grep -o '{"phrase":"[^"]*","count":[0-9]*}' | wc -l | tr -d ' ')

    echo "$entries_str" | grep -o '{"phrase":"[^"]*","count":[0-9]*}' | while IFS= read -r entry; do
        rank=$((rank + 1))

        phrase=$(echo "$entry" | grep -o '"phrase":"[^"]*"' | sed 's/"phrase":"//' | tr -d '"')
        shows=$(echo "$entry" | grep -o '"count":[0-9]*' | sed 's/"count"://')

        # stdout: show all if no CSV, or first STDOUT_MAX rows if CSV mode
        if [[ -z "$CSV_FILE" ]] || [[ "$rank" -le "$STDOUT_MAX" ]]; then
            echo "| $rank | $phrase | $(format_number "$shows") |"
        elif [[ "$rank" -eq $((STDOUT_MAX + 1)) ]]; then
            echo "| ... | ... and $((total - STDOUT_MAX)) more rows in CSV | ... |"
        fi

        # CSV: always write all rows
        if [[ -n "$CSV_FILE" ]]; then
            printf '%s%s%s%s%s%s%s\n' \
                "$rank" "$CSV_SEP" \
                "$(csv_escape "$phrase")" "$CSV_SEP" \
                "$shows" "$CSV_SEP" \
                "$type_label" >> "$CSV_FILE"
        fi
    done
}

# --- Parse topRequests array ---
# Extract array between "topRequests":[ and the matching ]
# Safe for flat arrays of {phrase, count} objects (no nested arrays)
top_entries=$(echo "$result" | sed -n 's/.*"topRequests":\[\([^]]*\)\].*/\1/p' | head -1)
process_entries "$top_entries" "top"

# --- Parse associations array ---
assoc_entries=$(echo "$result" | sed -n 's/.*"associations":\[\([^]]*\)\].*/\1/p' | head -1)

if [[ -n "$assoc_entries" ]] && echo "$assoc_entries" | grep -q '"phrase"'; then
    echo ""
    echo "=== Associations (similar queries) ==="
    echo ""
    echo "| # | Phrase | Impressions |"
    echo "|---|--------|-------------|"
    process_entries "$assoc_entries" "assoc"
fi

# --- Summary ---
echo ""
if [[ -n "$CSV_FILE" ]]; then
    csv_lines=$(($(wc -l < "$CSV_FILE") - 1))
    echo "CSV exported: $CSV_FILE ($csv_lines rows, sep='$CSV_SEP')"
fi

echo ""
echo "=== Raw JSON ==="
echo "$result" | head -c 2000
echo ""
echo "[truncated if > 2000 chars]"
