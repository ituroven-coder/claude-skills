# Model Selection

The skill supports two fal-hosted image backends behind the same `FAL_KEY`:

| Alias family | Resolved endpoint | Best for |
|--------------|-------------------|----------|
| `nano-banana`, `google`, `gemini` | `fal-ai/nano-banana-pro` | cheaper default runs, infographics, strong text rendering |
| `gpt`, `openai` | `openai/gpt-image-2` | stronger prompt adherence, photorealism, precise editing |

## Selection precedence

The scripts resolve the active model in this order:

1. CLI `--model`
2. `FAL_IMAGE_MODEL` in `config/.env`
3. `FAL_IMAGE_PROVIDER` in `config/.env`
4. fallback to `fal-ai/nano-banana-pro`

This means:

- old installs with only `FAL_KEY` still work
- a single request can explicitly force GPT or Nano Banana
- the agent should use `--model` when the user explicitly asks for a provider/model

## Agent mapping rules

Treat these phrases as equivalent:

- `GPT`, `OpenAI`, `ChatGPT Images`, `GPT Image` -> `--model gpt`
- `Nano Banana`, `Google`, `Gemini` -> `--model gemini`

If the user does **not** mention the model explicitly, let the config decide.

## Cost guidance

Nano Banana is the safer default for exploratory runs.

GPT Image 2 cost depends on:

- `quality`
- `image_size`
- edit vs generate complexity

As of April 22, 2026, fal's GPT Image 2 playground shows common high-quality outputs roughly in the `$0.15-$0.22` range depending on size. For rough planning, "about `$0.18`" is acceptable, but do not promise a fixed price without checking the live model page first.

Reference:

- https://fal.ai/models/openai/gpt-image-2/playground
