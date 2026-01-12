---
name: fal-ai-image
description: Generate images using fal.ai nano-banana model
---

# fal-ai-image

Generate images via fal.ai nano-banana model.

## Config

Requires `FAL_KEY` in `config/.env` or environment variable.
Get key: https://fal.ai/dashboard/keys

## Workflow

**IMPORTANT**: Always use `scripts/generate.sh` — do NOT call curl directly. The script handles API auth and polling automatically.

1. **Clarify params** (if not specified):
   - Aspect ratio: `1:1` (default), `16:9`, `9:16`, `4:3`, `3:4`, `3:2`, `2:3`, `21:9`, `5:4`, `4:5`
   - Resolution: `1K` (default), `2K`, `4K`
   - Num images: 1 (default)
   - Web search: disabled (default)

2. **Propose save path** (CLI only):
   - Check for `./images/`, `./assets/`, `./static/images/`
   - If exists → propose it
   - If not → propose `./generated/` or current dir
   - Suggest filename: `{short_description}_{timestamp}.png`
   - Ask: "Save to `./images/space_cat_20240115.png`? (or specify path)"

3. **Show price & confirm**:
   ```
   Cost: $0.15/image (4K: $0.30, +web search: +$0.015)
   Your request: 1 image, 1K, 1:1 = $0.15
   Confirm? (yes/no)
   ```

4. **Generate**:
   ```bash
   bash scripts/generate.sh \
     --prompt "a cat in space" \
     --aspect-ratio "1:1" \
     --resolution "1K" \
     --num-images 1 \
     --output-dir "./images" \
     --filename "space_cat"
   ```

5. **Show result**:
   - Script outputs JSON between `=== RESULT JSON ===` markers
   - Parse JSON yourself to extract image URLs and show to user
   - If saved locally: Read file via Read tool to display
   - Always provide URL as backup (expires in ~1 hour)

## Script params

| Param | Required | Default | Values |
|-------|----------|---------|--------|
| `--prompt` | yes | - | text |
| `--aspect-ratio` | no | 1:1 | 21:9, 16:9, 3:2, 4:3, 5:4, 1:1, 4:5, 3:4, 2:3, 9:16 |
| `--resolution` | no | 1K | 1K, 2K, 4K |
| `--num-images` | no | 1 | 1-4 |
| `--output-format` | no | png | png, jpeg, webp |
| `--output-dir` | no | - | path (if set, downloads image) |
| `--filename` | no | generated | base name without extension |
| `--web-search` | no | false | flag to enable web search |

## Pricing

- Base: **$0.15**/image
- 4K: **$0.30**/image (2x)
- Web search: **+$0.015**

Formula: `price = num_images * (resolution == "4K" ? 0.30 : 0.15) + (web_search ? 0.015 : 0)`
