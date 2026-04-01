#!/bin/sh
# Digest: summarize latest posts from subscribed X accounts
# Usage: bash scripts/digest.sh [--category ai] [--accounts "user1,user2"] [--period today]

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/common.sh"

load_config
parse_common_params "$@"
resolve_accounts

PERIOD="${PERIOD:-today}"
period_to_dates "$PERIOD"

# Check --prefer-cache BEFORE batch/single split
if [ -n "$PREFER_CACHE" ]; then
    _cached=$("$SCRIPT_DIR/find_latest.sh" --script digest --category "${CATEGORY:-}" --accounts "$ACCOUNTS" --period "$PERIOD" 2>/dev/null || true)
    if [ -n "$_cached" ] && [ -f "$_cached" ]; then
        echo "=== X Digest (cached): $PERIOD ===" >&2
        python3 -c "
import json, sys
data = json.load(open(sys.argv[1]))
text = data.get('text', data.get('summary', ''))
if text:
    print(text)
items = data.get('items', [])
if items:
    print()
    for it in items:
        print(f\"  @{it.get('author','')} | {it.get('date','')} | {it.get('summary','')}\")
ideas = data.get('ideas', [])
if ideas:
    print()
    print('Telegram post ideas:')
    for i, idea in enumerate(ideas, 1):
        print(f'  {i}. {idea}')
" "$_cached" | print_head "$LIMIT"
        echo "Artifact: $_cached" >&2
        exit 0
    fi
fi

SYSTEM_PROMPT='You are an X/Twitter research assistant. Always respond with valid JSON matching this schema:
{"items": [{"author": "@handle", "date": "ISO8601", "summary": "1-2 sentence summary", "engagement": "likes, reposts", "url": "https://x.com/...", "topic": "category"}], "ideas": ["Telegram post idea 1", "..."], "summary": "Overall narrative in 2-3 sentences"}
Do NOT wrap in markdown code fences. Return raw JSON only.'

# Count handles for batching (awk -F, counts fields correctly, wc -l is off-by-one)
_handle_count=$(printf '%s' "$ACCOUNTS" | awk -F, '{print NF}')

if [ "$_handle_count" -le "$MAX_HANDLES_PER_BATCH" ]; then
    # Single batch
    _prompt="Search X for the latest posts from these accounts: $ACCOUNTS. Period: from $FROM_DATE to $TO_DATE. For each notable post provide: author handle, date, summary (1-2 sentences), engagement metrics, post URL, topic. Highlight: breaking news, unique insights, hot takes, data/research. Suggest 3-5 Telegram post ideas based on the digest."

    grok_search "$_prompt" "$ACCOUNTS" "$FROM_DATE" "$TO_DATE" "$SYSTEM_PROMPT"
    _parsed=$(parse_structured_response < "$_RESPONSE_FILE")
else
    # Batch mode: split handles into groups of MAX_HANDLES_PER_BATCH
    _merge_dir="${TMPDIR:-/tmp}/xr_merge_$$"
    mkdir -p "$_merge_dir"
    trap 'rm -rf "$_merge_dir"' EXIT

    _batch_num=0
    _current_batch=""
    _current_count=0

    _old_ifs="$IFS"
    IFS=','
    for _h in $ACCOUNTS; do
        _h=$(printf '%s' "$_h" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [ -z "$_h" ] && continue

        if [ "$_current_count" -ge "$MAX_HANDLES_PER_BATCH" ]; then
            _prompt="Search X for the latest posts from these accounts: $_current_batch. Period: from $FROM_DATE to $TO_DATE. For each notable post provide: author handle, date, summary, engagement, post URL, topic."
            grok_search "$_prompt" "$_current_batch" "$FROM_DATE" "$TO_DATE" "$SYSTEM_PROMPT"
            parse_structured_response < "$_RESPONSE_FILE" > "$_merge_dir/batch_${_batch_num}.json"
            _batch_num=$(( _batch_num + 1 ))
            _current_batch=""
            _current_count=0
        fi

        if [ -n "$_current_batch" ]; then
            _current_batch="$_current_batch,$_h"
        else
            _current_batch="$_h"
        fi
        _current_count=$(( _current_count + 1 ))
    done
    IFS="$_old_ifs"

    # Run last batch
    if [ -n "$_current_batch" ]; then
        _prompt="Search X for the latest posts from these accounts: $_current_batch. Period: from $FROM_DATE to $TO_DATE. For each notable post provide: author handle, date, summary, engagement, post URL, topic."
        grok_search "$_prompt" "$_current_batch" "$FROM_DATE" "$TO_DATE" "$SYSTEM_PROMPT"
        parse_structured_response < "$_RESPONSE_FILE" > "$_merge_dir/batch_${_batch_num}.json"
    fi

    # Merge batches
    _parsed=$(python3 -c "
import json, glob, sys, os
merge_dir = sys.argv[1]
all_items = []
all_ideas = []
all_citations = []
all_text = []
seen_urls = set()
for f in sorted(glob.glob(os.path.join(merge_dir, 'batch_*.json'))):
    data = json.load(open(f))
    for item in data.get('items', []):
        url = item.get('url', '')
        if url and url in seen_urls:
            continue
        if url:
            seen_urls.add(url)
        all_items.append(item)
    all_ideas.extend(data.get('ideas', []))
    all_citations.extend(data.get('citations', []))
    if data.get('text'):
        all_text.append(data['text'])
# Sort items by date descending
all_items.sort(key=lambda x: x.get('date', ''), reverse=True)
result = {
    'items': all_items,
    'ideas': list(dict.fromkeys(all_ideas)),
    'summary': '',
    'text': '\\n---\\n'.join(all_text),
    'citations': sorted(set(c for c in all_citations if c))
}
print(json.dumps(result, ensure_ascii=False, indent=2))
" "$_merge_dir")
fi

# Save artifact
_extra=$(_CAT="${CATEGORY:-}" _HANDLES="$ACCOUNTS" _PERIOD="$PERIOD" _FROM="$FROM_DATE" _TO="$TO_DATE" python3 -c "
import json, os
print(json.dumps({
    'category': os.environ.get('_CAT', ''),
    'handles': [h for h in os.environ.get('_HANDLES', '').split(',') if h],
    'period': os.environ.get('_PERIOD', ''),
    'from_date': os.environ.get('_FROM', ''),
    'to_date': os.environ.get('_TO', ''),
}))")

_artifact=$(save_artifact "digest" "$_parsed" "$_extra")

# Output
echo "=== X Digest: $PERIOD (${FROM_DATE} — ${TO_DATE}) ===" >&2

python3 -c "
import json, sys
data = json.loads(sys.argv[1])
items = data.get('items', [])
if items:
    for it in items:
        author = it.get('author', '?')
        date = it.get('date', '')
        summary = it.get('summary', '')
        engagement = it.get('engagement', '')
        print(f'  {author} | {date} | {summary} | {engagement}')
else:
    text = data.get('text', '')
    if text:
        print(text)
ideas = data.get('ideas', [])
if ideas:
    print()
    print('Telegram post ideas:')
    for i, idea in enumerate(ideas, 1):
        print(f'  {i}. {idea}')
" "$_parsed" | print_head "$LIMIT"

echo "" >&2
echo "Artifact: $_artifact" >&2
