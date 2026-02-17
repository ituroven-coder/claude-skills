---
name: yandex-wordstat
description: |
  Search demand analysis via Yandex Wordstat API.
  Use when you need to: research demand, keyword analysis,
  query frequency, seasonality or regional demand.
  Top up to 2000 queries, associations, dynamics, CSV export.
  Missed demand analysis: XLSX export from Yandex Direct,
  phrase segmentation, semantic expansion, OR-query comparison.
  Triggers: missed demand.
---

# yandex-wordstat

Analyze search demand and keyword statistics using Yandex Wordstat API.

## Config

Requires `YANDEX_WORDSTAT_TOKEN` in `config/.env`.
See `config/README.md` for token setup instructions.

## Philosophy

1. **Skepticism to non-target demand** — high numbers don't mean quality traffic
2. **Creative semantic expansion** — think like a customer
3. **Always clarify region** — ask user for target region before analysis
4. **Show operators in reports** — include Wordstat operators for verification
5. **VERIFY INTENT via web search** — always check what people actually want to buy

## CRITICAL: Intent Verification

**Before marking ANY query as "target", verify intent via WebSearch!**

### The Problem

Query "kaolin wool for chimney" looks relevant for chimney seller, but:
- People search this to BUY WOOL, not chimneys
- They already HAVE a chimney and need insulation material
- This is NOT a target query for chimney sales!

### Verification Process

For every promising query, ASK YOURSELF:
1. **What does the person want to BUY?** (not just "what are they interested in")
2. **Will they buy OUR product from this search?**
3. **Or are they looking for something adjacent/complementary?**

### MANDATORY: Use WebSearch

**Always run WebSearch** to check what people actually search for.

Look at search results:
- What products are shown?
- What questions do people ask?
- Is this informational or transactional intent?

### Red Flags (likely NOT target)

- Query contains "for [your product]" — they need ACCESSORY, not your product
- Query about materials/components — they DIY, not buy finished product
- Query has "DIY", "how to make" — informational, not buying
- Query about repair/maintenance — they already own it

### Examples

| Query | Looks like | Actually | Target? |
|-------|------------|----------|---------|
| kaolin wool for chimney | chimney buyer | wool buyer | NO |
| buy chimney | chimney buyer | chimney buyer | YES |
| chimney insulation | chimney buyer | insulation DIYer | NO |
| sandwich chimney price | chimney buyer | chimney buyer | YES |
| accident victim | lawyer client | news reader | NO |
| lawyer after accident | lawyer client | lawyer client | YES |

### Workflow Update

1. Find queries in Wordstat
2. **WebSearch each promising query to verify intent**
3. Mark as target ONLY if intent matches the sale
4. Report both target AND rejected queries with reasoning

## Workflow

### STOP! Before any analysis:

1. **ASK user about region and WAIT for answer:**
   ```
   "Which region should I analyze?
   - All Russia (default)
   - Moscow and region
   - Specific city (which one?)"
   ```
   **DO NOT PROCEED until user answers!**

2. **ASK about business goal:**
   ```
   "What exactly do you sell/advertise?
   This is important for filtering non-target queries."
   ```

### After getting answers:

3. **Check connection**: `bash scripts/quota.sh`
4. **Run analysis** using appropriate script
5. **Verify intent via WebSearch** for each promising query
6. **Present results** with target/non-target separation

## Scripts

### quota.sh
Check API connection.
```bash
bash scripts/quota.sh
```

### top_requests.sh
Get top search phrases. Supports up to 2000 results and CSV export.
```bash
bash scripts/top_requests.sh \
  --phrase "query text" \
  --regions "213" \
  --devices "all"

# Extended: 500 results exported to CSV
bash scripts/top_requests.sh \
  --phrase "query text" \
  --limit 500 \
  --csv report.csv

# Max results with comma separator
bash scripts/top_requests.sh \
  --phrase "query text" \
  --limit 2000 \
  --csv full_report.csv \
  --sep ","
```

| Param | Required | Default | Values |
|-------|----------|---------|--------|
| `--phrase` | yes | - | text with operators |
| `--regions` | no | all | comma-separated IDs |
| `--devices` | no | all | all, desktop, phone, tablet |
| `--limit` | no | API default (50) | 1-2000 (maps to API numPhrases) |
| `--csv` | no | - | path to output CSV file |
| `--sep` | no | ; | CSV separator (; for RU Excel) |

#### Result types: Top Requests vs Associations

The output contains two sections (both in stdout and CSV):

- **top** (`topRequests`) — queries that **contain the words** from your phrase, sorted by frequency. These are direct variations of the search query.
- **assoc** (`associations`) — queries **similar by meaning** but not necessarily containing the same words, sorted by similarity. These are semantically related searches.

**For analysis:** `top` results are your primary keyword pool. `assoc` results are useful for semantic expansion but often contain noise — always verify intent before including them.

#### CSV export details

CSV format: UTF-8 with BOM, columns: `n;phrase;impressions;type`.
When `--csv` is set, stdout shows first 20 rows per section; full data goes to file.

#### Working with large CSV exports

When `--limit` is set to a high value (e.g. 500-2000), use CSV export and read the file in chunks:
```bash
# Export 2000 results
bash scripts/top_requests.sh --phrase "query" --limit 2000 --csv data.csv

# Read first 50 rows (header + data)
head -n 51 data.csv

# Read rows 51-100
tail -n +52 data.csv | head -50

# Count total rows
wc -l < data.csv

# Filter only associations
grep ";assoc$" data.csv
```

This approach lets the agent process large datasets without flooding stdout.

### dynamics.sh
Get search volume trends over time.
```bash
bash scripts/dynamics.sh \
  --phrase "query text" \
  --period "monthly" \
  --from-date "2025-01-01"
```

| Param | Required | Default | Values |
|-------|----------|---------|--------|
| `--phrase` | yes | - | text |
| `--period` | no | monthly | daily, weekly, monthly |
| `--from-date` | yes | - | YYYY-MM-DD |
| `--to-date` | no | today | YYYY-MM-DD |
| `--regions` | no | all | region IDs |
| `--devices` | no | all | all, desktop, phone, tablet |

### regions_stats.sh
Get regional distribution.
```bash
bash scripts/regions_stats.sh \
  --phrase "query text" \
  --region-type "cities"
```

| Param | Required | Default | Values |
|-------|----------|---------|--------|
| `--phrase` | yes | - | text |
| `--region-type` | no | all | cities, regions, all |
| `--devices` | no | all | all, desktop, phone, tablet |

### regions_tree.sh
Show common region IDs.
```bash
bash scripts/regions_tree.sh
```

### search_region.sh
Find region ID by name.
```bash
bash scripts/search_region.sh --name "Moscow"
```

## Wordstat Operators

### Quotes `"query"`
Shows demand ONLY for this exact phrase (no additional words).

```
"lawyer accident" -> "lawyer accident", "lawyers accident"
                     but NOT "lawyer for accident"
```

### Exclamation `!word`
Fixes exact word form.

```
!lawyer -> "lawyer for accident", "lawyer moscow"
           but NOT "lawyers", "lawyer's"
```

### Combination `"!word !word"`
Exact phrase + exact forms.

```
"!lawyer !for !accident" -> only "lawyer for accident"
```

### Minus `-word`
Exclude queries with this word.

```
lawyer accident -free -consultation
```

### Grouping `(a|b|c)`
Multiple variants in one query.

```
(lawyer|attorney) accident -> combined demand
```

### Stop words
**Always fix prepositions with `+`:**

Russian prepositions (na, v, k, za, s, po, iz, ot, do, dlya, bez, pri, pod, nad, mezhdu, cherez, ob, pered) are stop words in Wordstat — ignored without `+` operator.

The `build-query` script adds `+` to stop words automatically.

## Analysis Strategy

1. **Broad query**: `keyword` — see total volume
2. **Narrow with quotes**: `"keyword"` — exact phrase only
3. **Fix forms**: `"!keyword !preposition !modifier"` — exact match
4. **Clean with minus**: `keyword -free -online`
5. **Expand**: synonyms, related terms, client problems

## Popular Region IDs

| Region | ID |
|--------|-----|
| Russia | 225 |
| Moscow | 213 |
| Moscow region | 1 |
| Saint Petersburg | 2 |
| Yekaterinburg | 54 |
| Novosibirsk | 65 |
| Kazan | 43 |

Run `bash scripts/regions_tree.sh` for full list.

## Limits

- **10 requests/second**
- **1000 requests/day**

## Example Session

```
User: Find queries for chimney advertising

Claude: Which region should I analyze?
        And clarify - do you sell ready-made chimneys or
        materials for construction/insulation?

User: Moscow, we sell sandwich chimneys

Claude: [Runs analysis for region 213]

        Found queries. Verifying intent via web search...

        TARGET (buying chimneys):
        - "buy sandwich chimney" - 450 impressions
        - "chimney for sauna price" - 380 impressions

        NOT TARGET (buying something else):
        - "kaolin wool for chimney" - looking for insulation, not chimney
        - "chimney installation DIY" - DIY, not buyers
        - "chimney cleaning" - already own it, service query
```

### Key Points

1. **ALWAYS ask about region and wait for answer**
2. **ALWAYS clarify what the client sells**
3. **ALWAYS verify intent via WebSearch**
4. **Separate report into target/non-target with reasoning**

## Extended Scenarios

### Missed Demand Analysis
Analyze Yandex Direct campaign to find keywords not covered by current semantics.
Requirements: XLSX export from Yandex Direct (sheet named "Texts").
Details: [MISSED_DEMAND.md](MISSED_DEMAND.md)
