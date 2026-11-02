# Proposal

## Why

specview (`tools/specview.nim`) is the readable view of the OpenSpec specs and changes,
but it only exists as a page attached to PR runs or published by hand as a Claude
artifact, so there is no stable link to how Nanuq behaves today. Pietro asked
(2026-11-02) for it to be a published page like the Polars coverage map, linked from the
README's "How development works" and kept up to date.

## What Changes

- `docs/openspec.nim` renders `openspec.html` with the Nanuq theme: the dev log's header
  and footer, a short introduction to specs and changes, then specview's report (the
  changes, archived ones behind the checkbox, and every spec in full).
- `tools/specview.nim` exposes its report (`loadReport`, `renderNav`, `renderReport`,
  `reportCss`, `toggleJs`) so the page reuses it; the standalone page is unchanged.
- CI renders the page in the docs job (with full git history, for revisions) and
  publishes it at the site root. On `main`, pushes that change `openspec/`, `BACKLOG.md`
  or `tools/specview.nim` now run CI, so the published page follows every merged
  change. Pull requests touching only those files still skip CI.
- `nimble docs` renders it; the README ("How development works"), the dev-log index and
  the coverage page link to it.

## Capabilities

### Modified Capabilities
- `dev-log`: a living OpenSpec page next to the Polars coverage page.
- `ci`: render and deploy the living pages; on `main`, OpenSpec-only pushes run CI.

## Differences from Polars

None: this adds documentation, not API.

## Impact

- New `docs/openspec.nim`.
- `tools/specview.nim` (refactor, no change to its output), `.github/workflows/ci.yml`,
  `nanuq.nimble`, `docs/index.nim`, `docs/polars_coverage.nim`, `README.md`.
- An OpenSpec-only merge to `main` now costs a CI run (the Rust library comes from
  cache; tests and docs take a few minutes).
