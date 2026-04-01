#!/bin/sh
# Search: custom query search on X
# Usage: bash scripts/search.sh --query "что думают про Claude 4" [--period week] [--accounts "user1,user2"]

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/common.sh"

load_config
parse_common_params "$@"

if [ -z "$QUERY" ]; then
    echo "Error: --query is required." >&2
    echo "Usage: bash scripts/search.sh --query \"search query\" [--period week] [--accounts \"user1,user2\"]" >&2
    exit 1
fi

PERIOD="${PERIOD:-today}"
period_to_dates "$PERIOD"

# Normalize optional accounts filter
_handles=""
if [ -n "$ACCOUNTS" ]; then
    _handles=$(normalize_handles "$ACCOUNTS")
fi

SYSTEM_PROMPT='You are an X/Twitter research assistant. Always respond with valid JSON matching this schema:
{"items": [{"author": "@handle", "date": "ISO8601", "summary": "1-2 sentence summary", "engagement": "likes, reposts", "url": "https://x.com/...", "topic": "category"}], "ideas": ["Telegram post idea 1", "..."], "summary": "Overall search results narrative in 2-3 sentences"}
Do NOT wrap in markdown code fences. Return raw JSON only.'

_prompt="Search X for: $QUERY. Period: from $FROM_DATE to $TO_DATE.

Analyze the results and provide:
- Main narratives and themes in the discussion
- Key influencer opinions and takes
- Community sentiment (supportive vs critical)
- Most engaged/viral posts
- Unexpected or contrarian perspectives
- 3-5 concrete Telegram post ideas based on findings"

# Check --prefer-cache
if [ -n "$PREFER_CACHE" ]; then
    _cached=$("$SCRIPT_DIR/find_latest.sh" --script search --query "$QUERY" --period "$PERIOD" --accounts "$_handles" 2>/dev/null || true)
    if [ -n "$_cached" ] && [ -f "$_cached" ]; then
        echo "=== X Search (cached): $QUERY ===" >&2
        python3 -c "
import json, sys
data = json.load(open(sys.argv[1]))
items = data.get('items', [])
if items:
    for it in items:
        author = it.get('author', '?')
        summary = it.get('summary', '')
        engagement = it.get('engagement', '')
        print(f'  {author} | {summary} | {engagement}')
else:
    print(data.get('text', ''))
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

grok_search "$_prompt" "$_handles" "$FROM_DATE" "$TO_DATE" "$SYSTEM_PROMPT"
_parsed=$(parse_structured_response < "$_RESPONSE_FILE")

# Save artifact
_extra=$(_QUERY="$QUERY" _HANDLES="$_handles" _PERIOD="$PERIOD" _FROM="$FROM_DATE" _TO="$TO_DATE" python3 -c "
import json, os
handles = os.environ.get('_HANDLES', '')
print(json.dumps({
    'query': os.environ.get('_QUERY', ''),
    'handles': [h for h in handles.split(',') if h] if handles else None,
    'period': os.environ.get('_PERIOD', ''),
    'from_date': os.environ.get('_FROM', ''),
    'to_date': os.environ.get('_TO', ''),
}))")

_artifact=$(save_artifact "search" "$_parsed" "$_extra")

# Output
echo "=== X Search: '$QUERY' ($PERIOD) ===" >&2

python3 -c "
import json, sys
data = json.loads(sys.argv[1])
items = data.get('items', [])
summary = data.get('summary', '')
if summary:
    print(summary)
    print()
if items:
    for it in items:
        author = it.get('author', '?')
        date = it.get('date', '')
        summary_item = it.get('summary', '')
        engagement = it.get('engagement', '')
        print(f'  {author} | {date} | {summary_item} | {engagement}')
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
