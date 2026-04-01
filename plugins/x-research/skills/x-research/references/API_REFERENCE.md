# xAI Grok API Reference for x-research

## Endpoint

```
POST https://api.x.ai/v1/responses
Authorization: Bearer $XAI_API_KEY
Content-Type: application/json
```

## x_search tool

Server-side tool — Grok performs the search internally and returns synthesized results.

### Request format

```json
{
  "model": "grok-4-1-fast-reasoning",
  "input": [
    {"role": "developer", "content": "System prompt here"},
    {"role": "user", "content": "Search query here"}
  ],
  "tools": [
    {
      "type": "x_search",
      "allowed_x_handles": ["elonmusk", "sama"],
      "from_date": "2026-04-01",
      "to_date": "2026-04-02",
      "enable_image_understanding": false,
      "enable_video_understanding": false
    }
  ]
}
```

### x_search parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `allowed_x_handles` | array | Restrict to these accounts (max 10). Mutually exclusive with `excluded_x_handles` |
| `excluded_x_handles` | array | Exclude these accounts (max 10) |
| `from_date` | string | Start date, ISO8601 format |
| `to_date` | string | End date, ISO8601 format |
| `enable_image_understanding` | bool | Analyze images in posts |
| `enable_video_understanding` | bool | Analyze videos in posts (x_search only) |

### Response format

```json
{
  "id": "resp_...",
  "output": [
    {
      "type": "message",
      "content": [
        {
          "type": "output_text",
          "text": "Synthesized analysis text...",
          "annotations": [
            {
              "type": "url_citation",
              "url": "https://x.com/user/status/123",
              "title": "...",
              "start_index": 0,
              "end_index": 50
            }
          ]
        }
      ]
    }
  ],
  "usage": {
    "input_tokens": 1234,
    "output_tokens": 567
  }
}
```

## Models

| Model | Input $/1K | Output $/1K | Notes |
|-------|-----------|-------------|-------|
| `grok-4-1-fast-reasoning` | $0.20 | $0.50 | Fast, cheap, good for most tasks |
| `grok-4.20-reasoning` | $2.00 | $6.00 | Most capable, for deep analysis |
| `grok-4-1-fast-non-reasoning` | $0.20 | $0.50 | No chain-of-thought |
| `grok-4.20-non-reasoning` | $2.00 | $6.00 | No chain-of-thought |

Tool invocations: x_search billed separately (check current pricing at console.x.ai).

Full model list: https://docs.x.ai/developers/models

## Rate limits

Tier-based (cumulative spending since Jan 1, 2026):
- Tier 0: $0 (default) — limited RPM/TPM
- Tier 1: $50+ — increased limits
- Tier 2: $250+
- Tier 3: $1,000+
- Tier 4: $5,000+

On rate limit (429): retry after `Retry-After` header value.

Details: https://docs.x.ai/developers/rate-limits

## Search capabilities

The `x_search` tool supports multiple search modes (selected automatically by the model):
- **Keyword search** — traditional text matching with X advanced operators
- **Semantic search** — meaning-based search, catches related discussions
- **User search** — find accounts by name/handle
- **Thread fetch** — retrieve full thread by post reference

## Advanced operators in prompts

You can include X search operators in your prompt text:
- `from:username` — posts by specific user
- `since:YYYY-MM-DD` / `until:YYYY-MM-DD` — date range
- `min_faves:N` — minimum likes
- `filter:images` / `filter:videos` — media type
- `lang:en` / `lang:ru` — language filter

These are passed through the prompt, not as API parameters.

## Batch handling

`allowed_x_handles` is limited to 10 per request. For larger account lists:
1. Split into batches of 10
2. Make separate API calls per batch
3. Merge results: dedup by `item.url`, sort by `item.date`
