# Changelog

Notable changes to Nanuq. An entry is added when a change is implemented, usually when
its OpenSpec change is archived. Format based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- First proof of concept: Polars wrapped for Nim through a Rust C ABI (`rust/` crate
  `nanuq_ffi`, raw bindings in `src/nanuq/ffi.nim`, Nim API in `src/nanuq.nim`).
  Build DataFrames from Nim arrays or CSV, use expressions, and run lazy queries
  (filter, select, withColumns, groupBy/agg, sort, limit, explain, collect).
  Memory is managed by destructors, and errors arrive as `NanuqError`. (#1)
- Nanuq dev log built with nimib and a Nanuq theme, published on GitHub Pages. First
  post: "How Nanuq works", 2026-10-27. (#1)
- OpenSpec workflow with baseline specs (native-bridge, dataframe-api, ci),
  `BACKLOG.md` for ideas, and this changelog. (#4)
- Dev log post "Plotting with ggplotnim": plot a Nanuq DataFrame by converting columns
  to a Datamancer DataFrame, and the options for a smoother bridge. (#4)
- `tools/specview.nim`: an HTML review page for OpenSpec changes (stage, proposal,
  spec deltas with word diffs, tasks, file diffs), run in CI on planning PRs. (#5)
- Missing values: read columns and cells as `Option[T]`, `nullCount`, `hasNulls`,
  `series` from `Option`, `readCsv(nullValues = ...)`, and `isNull`, `isNotNull`,
  `fillNull` and `dropNulls` in queries. (#5)

### Changed
- `toSeq` reads a whole column in one FFI call (two for strings) instead of one per
  cell. It now raises up front, naming the column, when the column has nulls; read it as
  `Option[T]` instead. `float` reads integer columns and `string` reads any column. (#5)
- CI builds the Rust library only when `rust/` changes, and shares it with the test and
  docs jobs. Dropped the unused Polars `dtype-full` feature, which cuts the static
  library from 400 to 300 MB. (#2)
- CI skips commits that only touch Markdown, `LICENSE`, `.gitignore`, `openspec/` or
  `.claude/`. (#3, #4)
