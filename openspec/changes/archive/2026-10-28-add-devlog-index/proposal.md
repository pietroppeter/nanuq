# Proposal

## Why

The GitHub Pages root redirects to the latest dev-log post, so the other posts can only
be found through the README. There are three posts now and more will follow.

This takes up the BACKLOG.md entry "Blog index page" (Docs).

## What Changes

- New nimib page `docs/index.nim`, rendered to the site root with the Nanuq theme. It
  lists every post in `docs/blog`, newest first, with its date, title and a one-line
  summary, each linking to the post.
- The index is built from the rendered posts, so a new post needs no edit to the index:
  the date and link come from the post's dated file name (`2026-10-27-…html`), the
  title from its `<title>`, and the summary from a `<meta name="description">` that the
  theme writes.
- `useNanuqTheme` gets a `summary` parameter for that meta tag. The three existing posts
  get a summary.
- CI renders the posts, then the index, and publishes the index as the site root instead
  of the redirect. Posts keep their URLs under `blog/`.
- The README points to the index as well as the posts.

## Capabilities

### New Capabilities
- `dev-log`: how the dev log is organised and published (posts, index, theme).

### Modified Capabilities
- `ci`: the site root is the index instead of a redirect.

## Differences from Polars

None: this is about Nanuq's own docs site, not the Polars API.

## Impact

- `docs/index.nim` (new), `docs/nanuqtheme.nim`, the three posts in `docs/blog/`.
- `.github/workflows/ci.yml` (docs job), `README.md`.
- No library code changes.
