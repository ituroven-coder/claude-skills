---
name: yandex-wordstat
description: Analyze search demand via Yandex Wordstat API
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

## Workflow

1. **Check connection**: `bash scripts/quota.sh`
2. **Clarify region** with user (default: all Russia)
3. **Run analysis** using appropriate script
4. **Present results** with operators and recommendations

## Scripts

### quota.sh
Check API connection.
```bash
bash scripts/quota.sh
```

### top_requests.sh
Get top search phrases.
```bash
bash scripts/top_requests.sh \
  --phrase "юрист дтп" \
  --regions "213" \
  --devices "all"
```

| Param | Required | Default | Values |
|-------|----------|---------|--------|
| `--phrase` | yes | - | text with operators |
| `--regions` | no | all | comma-separated IDs |
| `--devices` | no | all | all, desktop, phone, tablet |

### dynamics.sh
Get search volume trends over time.
```bash
bash scripts/dynamics.sh \
  --phrase "юрист дтп" \
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
  --phrase "юрист дтп" \
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
bash scripts/search_region.sh --name "Москва"
```

## Wordstat Operators

### Quotes `"query"`
Shows demand ONLY for this exact phrase (no additional words).

```
"юрист дтп" → "юрист дтп", "юристы дтп"
             but NOT "юрист по дтп"
```

### Exclamation `!word`
Fixes exact word form.

```
!юрист → "юрист по дтп", "юрист москва"
         but NOT "юристы", "юриста"
```

### Combination `"!word !word"`
Exact phrase + exact forms.

```
"!юрист !по !дтп" → only "юрист по дтп"
```

### Minus `-word`
Exclude queries with this word.

```
юрист дтп -бесплатно -консультация
```

### Grouping `(a|b|c)`
Multiple variants in one query.

```
(юрист|адвокат) дтп → combined demand
```

### Stop words
**Always fix prepositions with `!`:**

```
юрист !по дтп    ← correct
юрист по дтп     ← "по" ignored!
```

## Analysis Strategy

1. **Broad query**: `юрист дтп` — see total volume
2. **Narrow with quotes**: `"юрист дтп"` — exact phrase only
3. **Fix forms**: `"!юрист !по !дтп"` — exact match
4. **Clean with minus**: `юрист дтп -бесплатно -онлайн`
5. **Expand**: synonyms, related terms, client problems

## Popular Region IDs

| Region | ID |
|--------|-----|
| Россия | 225 |
| Москва | 213 |
| Москва и область | 1 |
| Санкт-Петербург | 2 |
| Екатеринбург | 54 |
| Новосибирск | 65 |
| Казань | 43 |

Run `bash scripts/regions_tree.sh` for full list.

## Limits

- **10 requests/second**
- **1000 requests/day**

## Example Session

```
User: Analyze "юрист по дтп" in Moscow

1. bash scripts/quota.sh
   → API OK

2. bash scripts/search_region.sh --name "Москва"
   → ID 213

3. bash scripts/top_requests.sh --phrase "юрист !по дтп" --regions 213
   → Top phrases

4. bash scripts/dynamics.sh --phrase "юрист дтп" --from-date 2025-01-01
   → Monthly trends

5. Present results with recommendations
```
