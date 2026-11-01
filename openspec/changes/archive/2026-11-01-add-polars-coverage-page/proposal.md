# Proposal

## Why

The Polars coverage map (every Polars feature group, and whether Nanuq has it) was made
on 2026-10-28 as a planning artifact outside the repo, and it went stale after four
releases. Pietro asked (2026-11-01) for it to be a separate document that gets updated,
not a dev-log post, and chose a page on the Nanuq site built from a data file in the
repo.

## What Changes

- `docs/coverage/polars.json`: the catalogue, 128 feature groups in 14 areas, each with
  the Polars names, a status per Nanuq version (has it, partly, missing, not planned), a
  note on what is still missing and a priority for open groups. A version left out of a
  row keeps the previous version's status, so a release only adds the rows that change.
- `docs/polars_coverage.nim`: renders it to `polars_coverage.html` with the Nanuq theme:
  totals per version, a table by area, the groups still open by priority, and the
  catalogue. It does not import Nanuq.
- The dev-log index links to the page; CI and `nimble docs` render it and publish it at
  the site root.
- Each release PR refreshes the data (a new version entry and the rows that changed).

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
