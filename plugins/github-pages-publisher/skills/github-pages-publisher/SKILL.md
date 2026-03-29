---
name: github-pages-publisher
description: Publish static page artifacts from the publisher workspace to a GitHub Pages repository using a fine-grained token. Use when a React/static page artifact is already prepared and needs to be copied into the Pages repo under a strict year/year-month/page-slug directory layout, then committed and pushed, with a final public artifact URL returned.
---

# GitHub Pages Publisher

Publish already-built static artifacts to a GitHub Pages repository.

This skill is the **deployment/output layer** for page artifacts created by other skills.

## Required repository layout

Every published artifact must go into this path shape inside the target repo:

`<year>/<year>-<month>/<page-slug>/`

Example:
- `2026/2026-03/my-landing-page/`

Never publish flat at repo root.
Never skip the year or year-month nesting.

## What this skill expects

Input should already exist as one of these:
- a folder of built static files
- a single HTML artifact plus local assets
- a small static site ready to serve from a subdirectory

This skill should not do major frontend design work. It should package and publish what already exists.

## Default publishing rules

- preserve relative asset paths when possible
- prefer `index.html` as entrypoint inside the target page directory
- keep the output self-contained inside the page folder
- avoid breaking existing published pages
- if the same slug is republished, update the existing folder contents deliberately

## URL contract

Always return the final public URL of the artifact.

Assume GitHub Pages serves from the repo's configured Pages base URL.
The final URL should be:

`<pages-base-url>/<year>/<year>-<month>/<page-slug>/`

or, if needed explicitly:

`.../<page-slug>/index.html`

Prefer the clean directory URL when it resolves correctly.

## Workflow

1. Determine the publish date bucket:
   - year = `YYYY`
   - year-month = `YYYY-MM`
2. Verify the local artifact has already passed viewport validation at **1440px desktop** and **375px mobile**
3. Create or update target directory:
   - `<year>/<year-month>/<page-slug>/`
4. Copy artifact files into that directory
5. Verify there is an entrypoint (`index.html` normally)
6. Run a second local viewport validation against the publish-ready artifact copy before any push
7. Commit and push to the Pages repo using the configured fine-grained token workflow
8. Return the final public URL

## Slug rules

- use lowercase letters, digits, and hyphens
- keep it short and descriptive
- avoid spaces, underscores, Cyrillic, timestamps unless needed for uniqueness
- if the title is user-facing, the slug can still be normalized separately

## Mandatory local validation gate
Publish is **not complete** until the artifact passes a local viewport/layout check before push.

Required gate:
- run `python3 scripts/validate_layout.py --source <artifact-dir-or-html>` from this skill directory, or invoke the same script by absolute/relative path
- validate at minimum:
  - **desktop 1440x1080**
  - **small mobile 375x812**
- fail the publish if any of these are true:
  - horizontal overflow exists
  - no hero / main / primary heading is visible in the first viewport
  - on mobile, the hero / h1 starts too high, collides with the top safe-area / status-bar zone, or reads like a cropped first-screen headline
  - the screenshot sanity check fails
- store validation screenshots and JSON report locally and mention their path in the final result when useful

If the artifact uses a custom hero wrapper, prefer a stable hook such as `data-hero`. You may also pass one or more selectors with `--hero-selector`.

A successful git push without this validation does **not** count as a finished publish under this skill.

## Safety rules

- do not delete unrelated directories in the Pages repo
- only replace contents of the target page directory being published
- if overwriting, say so in the result
- do not expose the token in output, logs, or committed files
- do not push artifacts that fail local viewport validation

## Config

Read `config/README.md` for required environment variables and URL derivation.

## References

Read if needed:
- `references/publish-checklist.md` — operational checklist before pushing
- `references/layout-validation.md` — viewport set, required checks, validator usage, and expected evidence
