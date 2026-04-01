#!/bin/sh
# Find latest matching artifact from the index
# Usage: bash scripts/find_latest.sh --script digest [--category ai] [--query "..."] [--period today] [--accounts "a,b"] [--topics "X,Y"] [--url "..."]
# Prints: absolute path to latest matching artifact, or exits 1 if none found
# All provided filters must match; omitted filters are ignored.

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CACHE_DIR="$SKILL_DIR/cache"
INDEX_FILE="$CACHE_DIR/index.jsonl"

# Parse args
_script=""
_category=""
_query=""
_period=""
_accounts=""
_topics=""
_url=""

while [ $# -gt 0 ]; do
    case "$1" in
        --script)    _script="$2"; shift 2 ;;
        --category)  _category="$2"; shift 2 ;;
        --query)     _query="$2"; shift 2 ;;
        --period)    _period="$2"; shift 2 ;;
        --accounts)  _accounts="$2"; shift 2 ;;
        --topics)    _topics="$2"; shift 2 ;;
        --url)       _url="$2"; shift 2 ;;
        *)           shift ;;
    esac
done

if [ -z "$_script" ]; then
    echo "Error: --script is required." >&2
    exit 1
fi

if [ ! -f "$INDEX_FILE" ]; then
    exit 1
fi

_FIND_SCRIPT="$_script" \
_FIND_CATEGORY="$_category" \
_FIND_QUERY="$_query" \
_FIND_PERIOD="$_period" \
_FIND_ACCOUNTS="$_accounts" \
_FIND_TOPICS="$_topics" \
_FIND_URL="$_url" \
_FIND_CACHE="$CACHE_DIR" \
python3 -c "
import json, os, sys

cache_dir = os.environ['_FIND_CACHE']
index_file = os.path.join(cache_dir, 'index.jsonl')

# Filters from env
filters = {}
for key in ('script', 'category', 'query', 'period', 'url'):
    val = os.environ.get(f'_FIND_{key.upper()}', '')
    if val:
        filters[key] = val

# Handles: compare as sorted sets
accounts_filter = os.environ.get('_FIND_ACCOUNTS', '')
if accounts_filter:
    filters['_handles_set'] = sorted(set(h.strip() for h in accounts_filter.split(',') if h.strip()))

# Topics: compare as string
topics_filter = os.environ.get('_FIND_TOPICS', '')
if topics_filter:
    filters['topics'] = topics_filter

matches = []
with open(index_file, 'r') as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            continue

        ok = True
        for key, val in filters.items():
            if key == '_handles_set':
                entry_handles = entry.get('handles', [])
                if isinstance(entry_handles, list):
                    entry_set = sorted(set(entry_handles))
                else:
                    entry_set = sorted(set(h.strip() for h in str(entry_handles).split(',') if h.strip()))
                if entry_set != val:
                    ok = False
                    break
            else:
                if entry.get(key, '') != val:
                    ok = False
                    break
        if ok:
            matches.append(entry)

if not matches:
    sys.exit(1)

matches.sort(key=lambda x: x.get('created_at', ''), reverse=True)
best = matches[0]
path = os.path.join(cache_dir, best['path'])
if os.path.isfile(path):
    print(path)
else:
    sys.exit(1)
"
