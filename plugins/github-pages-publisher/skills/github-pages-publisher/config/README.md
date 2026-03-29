# Config

Required environment variables:

- `GHPAGES_TOKEN` — fine-grained GitHub token with contents write access to the target repo
- `GHPAGES_REPO` — `owner/repo`
- `GHPAGES_BRANCH` — target branch (usually `main` or `gh-pages`)
- `GHPAGES_PAGES_BASE_URL` — public Pages base URL, for example `https://example.github.io/repo`

The publisher writes artifacts into:
- `YYYY/YYYY-MM/page-slug/`

The final URL is derived as:
- `<GHPAGES_PAGES_BASE_URL>/YYYY/YYYY-MM/page-slug/`
