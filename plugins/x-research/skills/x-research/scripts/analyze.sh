#!/bin/sh
# Analyze: deep analysis of a specific X post, thread, or topic
# Usage: bash scripts/analyze.sh --query "post description or topic" [--url "https://x.com/..."] [--period today]

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/common.sh"

load_config
parse_common_params "$@"

if [ -z "$QUERY" ] && [ -z "$URL" ]; then
    echo "Error: --query or --url is required." >&2
    echo "Usage: bash scripts/analyze.sh --query \"topic or post description\" [--url \"https://x.com/...\"]" >&2
    exit 1
fi

# When URL is provided, don't restrict date range — the post could be from any date.
# Only apply date filter for topic-based analysis without a specific URL.
if [ -n "$URL" ]; then
    PERIOD="${PERIOD:-}"
    FROM_DATE=""
    TO_DATE=""
    if [ -n "$PERIOD" ]; then
        period_to_dates "$PERIOD"
    fi
else
    PERIOD="${PERIOD:-today}"
    period_to_dates "$PERIOD"
fi

# Build prompt
_target=""
if [ -n "$URL" ]; then
    _target="Post/thread URL: $URL. Fetch this specific post and its full reply thread."
fi
if [ -n "$QUERY" ]; then
    if [ -n "$_target" ]; then
        _target="$_target Context: $QUERY"
    else
        _target="Topic/post: $QUERY"
    fi
fi

_period_hint=""
if [ -n "$FROM_DATE" ]; then
    _period_hint=" Period for replies/discussion: from $FROM_DATE to $TO_DATE."
fi

_prompt="Find and analyze this X post/thread/topic: ${_target}.${_period_hint}

Provide a thorough analysis:
1. **Main thesis** — what is the core message or claim
2. **Key arguments** — supporting points, evidence, data cited
3. **Community reaction** — overall tone (positive/negative/mixed), main counter-arguments, notable replies
4. **Interesting findings** — unexpected insights, unique perspectives from the discussion
5. **Sentiment breakdown** — approximate ratio of supportive vs critical vs neutral reactions
6. **Key voices** — notable accounts that engaged with this topic
7. **Telegram post angle** — 2-3 concrete ideas for how to turn this into an engaging Telegram post"

# Check --prefer-cache
if [ -n "$PREFER_CACHE" ]; then
    _cached=$("$SCRIPT_DIR/find_latest.sh" --script analyze --query "$QUERY" --url "${URL:-}" --period "${PERIOD:-}" 2>/dev/null || true)
    if [ -n "$_cached" ] && [ -f "$_cached" ]; then
        echo "=== X Analysis (cached) ===" >&2
        python3 -c "
import json, sys
data = json.load(open(sys.argv[1]))
print(data.get('text', ''))
" "$_cached" | print_head "$LIMIT"
        echo "Artifact: $_cached" >&2
        exit 0
    fi
fi

# No structured output for analyze — free-form text is better for deep analysis
# When URL given without period, skip date filters so x_search can find the post regardless of age
grok_search "$_prompt" "" "${FROM_DATE:-}" "${TO_DATE:-}"

# Parse as plain text (not structured items)
_parsed=$(python3 -c "
import json, sys
data = json.load(sys.stdin)
text_parts = []
citations = []
for item in data.get('output', []):
    if item.get('type') == 'message':
        for c in item.get('content', []):
            if c.get('type') == 'output_text':
                text_parts.append(c['text'])
            for ann in c.get('annotations', []):
                if ann.get('type') == 'url_citation':
                    citations.append(ann.get('url', ''))
result = {
    'items': [],
    'ideas': [],
    'summary': '',
    'text': '\\n'.join(text_parts),
    'citations': sorted(set(c for c in citations if c))
}
print(json.dumps(result, ensure_ascii=False, indent=2))
" < "$_RESPONSE_FILE")

# Save artifact
_extra=$(_QUERY="$QUERY" _URL="${URL:-}" _PERIOD="${PERIOD:-}" _FROM="${FROM_DATE:-}" _TO="${TO_DATE:-}" python3 -c "
import json, os
print(json.dumps({
    'query': os.environ.get('_QUERY', ''),
    'url': os.environ.get('_URL', ''),
    'period': os.environ.get('_PERIOD', ''),
    'from_date': os.environ.get('_FROM', ''),
    'to_date': os.environ.get('_TO', ''),
}))")

_artifact=$(save_artifact "analyze" "$_parsed" "$_extra")

# Output
echo "=== X Analysis: $PERIOD ===" >&2

python3 -c "
import json, sys
data = json.loads(sys.argv[1])
text = data.get('text', '')
if text:
    print(text)
citations = data.get('citations', [])
if citations:
    print()
    print('--- Sources ---')
    for u in citations:
        print(u)
" "$_parsed" | print_head "$LIMIT"

echo "" >&2
echo "Artifact: $_artifact" >&2
