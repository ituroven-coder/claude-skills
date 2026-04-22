# Configuration

The skill supports **two fal-hosted image models** behind the same `FAL_KEY`:

| Selector | Resolved model | Best for |
|----------|----------------|----------|
| default / `google` | `fal-ai/nano-banana-pro` | backward-compatible default, infographics, lower cost |
| `openai` | `openai/gpt-image-2` | stronger prompt adherence, photorealism, detailed edits |

No separate OpenAI key is required when you use the fal-hosted GPT model.

## One-off override from CLI

Both `generate.sh` and `edit.sh` support:

```bash
--model VALUE
```

Supported aliases:

| `--model` value | Resolved model |
|-----------------|----------------|
| `nano-banana`, `google`, `gemini` | `fal-ai/nano-banana-pro` |
| `gpt`, `openai` | `openai/gpt-image-2` |
| exact endpoint IDs | same endpoint |

Examples:

```bash
sh scripts/generate.sh --model gpt --prompt "studio product render"
sh scripts/generate.sh --model gemini --prompt "text-heavy infographic"
sh scripts/edit.sh --model openai --image-urls "$URL" --prompt "premium ad retouch"
```

Use this when the user explicitly asks for a specific model or asks which options are available.

`edit.sh` also supports:

```bash
--mask-url URL
```

This is passed through to `openai/gpt-image-2/edit` and is useful when you want to constrain the edit to a specific region. Nano Banana does not support this flag in the current skill.

## Quick start

1. Get an API key at https://fal.ai/dashboard/keys
2. Copy `.env.example` to `.env`
3. Set `FAL_KEY`

Minimal config keeps the old behavior:

```env
FAL_KEY=your_fal_api_key_here
```

This resolves to **Nano Banana Pro** automatically.

## Switch to OpenAI GPT Image 2

Use the human-friendly selector:

```env
FAL_KEY=your_fal_api_key_here
FAL_IMAGE_PROVIDER=openai
FAL_IMAGE_OPENAI_QUALITY=medium
```

Or pin the exact fal model ID:

```env
FAL_KEY=your_fal_api_key_here
FAL_IMAGE_MODEL=openai/gpt-image-2
FAL_IMAGE_OPENAI_QUALITY=medium
```

## Selector precedence

Selection in `scripts/common.sh` is intentionally simple:

1. `--model` — one-off CLI override
2. `FAL_IMAGE_MODEL` — exact model override in config
3. `FAL_IMAGE_PROVIDER` — `google` or `openai`
4. Nothing set — fallback to `fal-ai/nano-banana-pro`

That means older installs with only `FAL_KEY` keep working without any changes, while a single run can still force GPT or Nano Banana.

## Parameter mapping by model

### Nano Banana Pro

Native knobs:

- `--aspect-ratio`
- `--resolution`
- `--web-search` (generate only)

### OpenAI GPT Image 2

Native knobs:

- `--image-size`
- `--quality`
- `--mask-url` in `edit.sh`

Supported `--image-size` forms:

- preset: `square_hd`, `square`, `portrait_4_3`, `portrait_16_9`, `landscape_4_3`, `landscape_16_9`
- custom size: `WIDTHxHEIGHT` (for example `1536x1024`)
- `auto` in `edit.sh`

Compatibility layer:

- if `--image-size` is omitted, the scripts derive a valid OpenAI `image_size` from `--aspect-ratio` + `--resolution`
- this keeps the old CLI shape usable after switching the provider in config

## Quality default for OpenAI

fal's GPT Image 2 schema defaults `quality` to `high`, but this skill uses:

```env
FAL_IMAGE_OPENAI_QUALITY=medium
```

as the default unless you override it via `--quality`.

Reason: `high` can make exploratory runs noticeably more expensive than Nano Banana. `medium` is a safer default for iteration; use `--quality high` for final renders.

As of April 22, 2026, fal's GPT Image 2 playground shows common high-quality renders landing roughly around `$0.15-$0.22` per image depending on size, so the "about $0.18" rule of thumb is reasonable for user guidance. Verify current prices on the model page before promising a number: [GPT Image 2 pricing](https://fal.ai/models/openai/gpt-image-2/playground).

## Examples

### Default Nano Banana

```bash
sh scripts/generate.sh \
  --prompt "poster about coffee brewing" \
  --aspect-ratio "9:16" \
  --resolution "1K"
```

### OpenAI GPT Image 2 with explicit preset size

```bash
sh scripts/generate.sh \
  --model "gpt" \
  --prompt "realistic product hero shot, clean label typography" \
  --image-size "landscape_4_3" \
  --quality "medium"
```

### OpenAI GPT Image 2 while keeping old flags

```bash
sh scripts/generate.sh \
  --model "openai" \
  --prompt "editorial-style fashion photo" \
  --aspect-ratio "4:3" \
  --resolution "2K"
```

The script will derive a valid `image_size` object for OpenAI automatically.

## Troubleshooting

### `FAL_KEY not found`

Set `FAL_KEY` in `config/.env` or the shell environment.

### `Unsupported FAL_IMAGE_PROVIDER`

Use only:

```env
FAL_IMAGE_PROVIDER=google
FAL_IMAGE_PROVIDER=openai
```

### `Unsupported FAL_IMAGE_MODEL`

Use only:

```env
FAL_IMAGE_MODEL=fal-ai/nano-banana-pro
FAL_IMAGE_MODEL=openai/gpt-image-2
```

### `OpenAI image_size width and height must be multiples of 16`

When you pass custom `--image-size`, use dimensions like:

- `1024x1024`
- `1536x1024`
- `1920x1088`

## References

- Nano Banana Pro API: https://fal.ai/models/fal-ai/nano-banana-pro/api
- Nano Banana Pro edit API: https://fal.ai/models/fal-ai/nano-banana-pro/edit/api
- GPT Image 2 API: https://fal.ai/models/openai/gpt-image-2/api
- GPT Image 2 edit API: https://fal.ai/models/openai/gpt-image-2/edit/api
