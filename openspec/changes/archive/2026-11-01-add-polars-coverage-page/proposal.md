# Proposal

## Why

The Polars coverage map (every Polars feature group, and whether Nanuq has it) was made
on 2026-10-28 as a planning artifact outside the repo, and it went stale after four
releases. Pietro asked (2026-11-01) for it to be a separate document that gets updated,
not a dev-log post, and chose a page on the Nanuq site built from a data file in the
repo.

## What Changes

- `docs/coverage/polars.json`: the catalogue for the latest release, 128 feature groups
  in 14 areas, each with the Polars names, a status (has it, partly, missing, not
  planned), a note on what is still missing, a priority for open groups and a mark on
  the groups new in that release. Older releases are not kept (Pietro, 2026-11-02);
  once the next release has a plan, rows can name the release that plans them.
- `docs/polars_coverage.nim`: renders it to `polars_coverage.html` with the Nanuq theme:
  release totals, a table by area, the groups still open by priority, and the
  catalogue, with the dev log's header and footer. It does not import Nanuq.
- The dev-log index links to the page; CI and `nimble docs` render it and publish it at
  the site root.
- Each release PR refreshes the data (the release, the changed rows and their new-marks).

## Capabilities

### Modified Capabilities
- `dev-log`: a living Polars coverage page next to the dated posts.

## Differences from Polars

None: this adds documentation, not API. The page uses Polars' Python names and says
that Nanuq spells them in camelCase.

## Impact

- New `docs/coverage/polars.json`, `docs/polars_coverage.nim`.
- `docs/index.nim` (link), `.github/workflows/ci.yml` and `nanuq.nimble` (render and
  publish the page).
