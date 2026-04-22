# Editing Workflows

## Generate vs Edit

Use `generate.sh` when the user wants a brand new image from text.

Use `edit.sh` when at least one source image matters:

- preserve composition from a source
- restyle an existing picture
- replace or add objects
- modify only one area of an image

## Reference images

`edit.sh` accepts:

- public URLs directly in `--image-urls`
- local files after uploading through `scripts/upload.sh`

When several input images are passed to GPT edit, the mask applies to the **first** image.

## `mask_url`

`mask_url` is currently supported only for `openai/gpt-image-2/edit`.

Purpose:

- tells the model which region should be edited
- keeps the rest of the image more stable
- is best for inpainting-style changes such as swapping one object, changing text in one block, replacing a sign, retouching a face region, etc.

Important nuance from OpenAI's image docs:

- with GPT Image, the mask is **guidance**, not a perfect hard boundary
- the model usually follows the masked region, but may bleed slightly outside it if the prompt implies broader changes

## Mask requirements

Practical requirements for reliable results:

- mask and source image should have the same size
- mask should have an alpha channel
- transparent area should represent the region to replace
- keep the prompt tightly scoped to the masked area when you want localized edits

## When to use a mask

Use a mask when the user says something like:

- "замени только вывеску"
- "поменяй текст только в этом блоке"
- "убери объект справа, остальное не трогай"
- "сделай ретушь только лица"

Do **not** bother with `mask_url` when the user wants a broad restyle of the whole image. In that case plain `edit.sh` with references is simpler.

## Prompting tips for masked edits

- explicitly mention what must stay unchanged
- name the target area in the prompt
- avoid global style rewrites unless you actually want spillover outside the mask

Example:

```bash
sh scripts/edit.sh \
  --model gpt \
  --image-urls "https://example.com/base.png" \
  --mask-url "https://example.com/mask.png" \
  --image-size auto \
  --quality medium \
  --prompt "Replace only the masked area with a matte red ceramic mug. Keep the rest of the poster unchanged."
```

References:

- fal GPT edit API: https://fal.ai/models/openai/gpt-image-2/edit/api
- OpenAI image generation guide: https://platform.openai.com/docs/guides/image-generation
