#!/bin/sh
# Trending: find hot topics and discussions on X by interest areas
# Usage: bash scripts/trending.sh [--category ai] [--topics "AI,LLM"] [--period today]

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/common.sh"

load_config
parse_common_params "$@"
resolve_topics

PERIOD="${PERIOD:-today}"
period_to_dates "$PERIOD"

SYSTEM_PROMPT='You are an X/Twitter research assistant. Always respond with valid JSON matching this schema:
{"items": [{"topic": "topic name", "summary": "2-3 sentence description of the discussion", "sentiment": "positive/negative/mixed/neutral", "key_voices": ["@handle1", "@handle2"], "engagement": "approximate scale", "url": "most relevant post URL"}], "ideas": ["Telegram post idea 1", "..."], "summary": "Overall trending narrative in 2-3 sentences"}
Do NOT wrap in markdown code fences. Return raw JSON only.'

_prompt="Search X for the most discussed and interesting topics about: $TOPICS. Period: from $FROM_DATE to $TO_DATE.

Find and analyze:
- Breaking news and announcements
- Hot debates and controversies
- Viral posts and threads
- Expert opinions and predictions
- Unexpected findings or contrarian takes
- Data, research, or reports being shared

For each notable topic/discussion: summarize the core narrative, assess sentiment, identify key voices, and suggest a Telegram post angle."

# Check --prefer-cache
if [ -n "$PREFER_CACHE" ]; then
    _cached=$("$SCRIPT_DIR/find_latest.sh" --script trending --category "${CATEGORY:-}" --topics "$TOPICS" --period "$PERIOD" 2>/dev/null || true)
    if [ -n "$_cached" ] && [ -f "$_cached" ]; then
        echo "=== X Trending (cached): $TOPICS ===" >&2
        python3 -c "
import json, sys
data = json.load(open(sys.argv[1]))
items = data.get('items', [])
if items:
    for it in items:
        topic = it.get('topic', '?')
        summary = it.get('summary', '')
        sentiment = it.get('sentiment', '')
        print(f'  [{sentiment}] {topic}: {summary}')
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

grok_search "$_prompt" "" "$FROM_DATE" "$TO_DATE" "$SYSTEM_PROMPT"
_parsed=$(parse_structured_response < "$_RESPONSE_FILE")

# Save artifact
_extra=$(_CAT="${CATEGORY:-}" _TOPICS="$TOPICS" _PERIOD="$PERIOD" _FROM="$FROM_DATE" _TO="$TO_DATE" python3 -c "
import json, os
print(json.dumps({
    'category': os.environ.get('_CAT', ''),
    'topics': os.environ.get('_TOPICS', ''),
    'period': os.environ.get('_PERIOD', ''),
    'from_date': os.environ.get('_FROM', ''),
    'to_date': os.environ.get('_TO', ''),
}))")

_artifact=$(save_artifact "trending" "$_parsed" "$_extra")

# Output
echo "=== X Trending: $TOPICS ($PERIOD) ===" >&2

python3 -c "
import json, sys
data = json.loads(sys.argv[1])
items = data.get('items', [])
if items:
    for it in items:
        topic = it.get('topic', '?')
        summary = it.get('summary', '')
        sentiment = it.get('sentiment', '')
        voices = ', '.join(it.get('key_voices', [])[:3])
        print(f'  [{sentiment}] {topic}')
        print(f'    {summary}')
        if voices:
            print(f'    Voices: {voices}')
        print()
else:
    text = data.get('text', '')
    if text:
        print(text)
ideas = data.get('ideas', [])
if ideas:
    print('Telegram post ideas:')
    for i, idea in enumerate(ideas, 1):
        print(f'  {i}. {idea}')
" "$_parsed" | print_head "$LIMIT"

echo "" >&2
echo "Artifact: $_artifact" >&2
