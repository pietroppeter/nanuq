# Changelog

Notable changes to Nanuq. An entry is added when a change is implemented, usually when
its OpenSpec change is archived. Format based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- Data types: `DataType` with Polars-named constants (`Int64`, `String`, ...), `dtypes`,
  `schema`, `collectSchema`, `dataType(T)`, and `cast` on expressions and frames, taking
  a Nim type (`col("a").cast(int32)`) or `DataType` values (`df.cast({"a": Int32})`),
  strict by default. The wrapper crate is `0.2.0-dev` until `lib-v0.2.0`. (#26)
- Joins: `join` on `on` or `leftOn`/`rightOn` keys (names or expressions) and cross
  joins, with `how`, `suffix`, `validate`, `nullsEqual`, `coalesce` and `maintainOrder`. (#28)
- Concatenation: `concat` of frames, vertical (strict or relaxed), horizontal or
  diagonal. (#28)
- API conventions, written down in the README and the `api-conventions` spec: Polars
  names in camelCase, option values as pure enums with Rust Polars names. (#28)
- Frame verbs on LazyFrame and DataFrame: `drop`, `rename`, `head` (lazy), `tail`,
  `slice`, `reverse`, `withRowIndex`, and `unique` with `keep` (`UniqueKeepStrategy`)
  and `maintainOrder`. (#30)
- Sorting by several keys (names or expressions) with per-key `descending` and
  `nullsLast`, and `maintainOrder`; the one-column `sort` gains `nullsLast` and
  `maintainOrder`. (#30)
- `sample` on DataFrame, by `n` or `fraction`, with `withReplacement`, `shuffle` and
  `seed`. (#30) `setRandomSeed` for Polars' global generator, and `seed = 42` as a plain int. (#31)
- Conditional expressions: the Polars chain `` `when`(c).then(a).otherwise(b) `` and the
  `choose` macro over `if`/`elif`/`else`; strings in branches are values. (#33)
- Expressions: `isIn`, `isBetween` (`ClosedInterval`), `mod` and `div` (Polars' floor
  semantics), `^`/`pow`, `abs`, unary `-`, `round` (`RoundMode`), `median`, `var`,
  `quantile` (`QuantileMethod`), `len`, and `ddof` on `std`. (#33)
- Null fill strategies (`fillNull(Forward)`, `FillNullStrategy`, `forwardFill`,
  `backwardFill`) and window expressions (`over`). (#33)
- Column selectors: `col(SomeNumber)` and the other Nim typeclasses, `col(int)`,
  `col(float, string)`, `col("a", "b")`, `all()`, `exclude`, and `name.suffix` /
  `name.prefix` for the output names. (#35)
- CSV: `scanCsv` for lazy reads of a file or a glob; read options on `scanCsv` and
  `readCsv` (`separator`, `hasHeader`, `nullValues`, `schemaOverrides`, `skipRows`,
  `nRows`, `columns`, `inferSchemaLength`, `ignoreErrors`, `decimalComma`); write
  options on `writeCsv` (`separator`, `includeHeader`, `nullValue`, `quoteStyle` with
  `QuoteStyle`, `floatPrecision`, `decimalComma`). `readCsv` is now
  `scanCsv(...).collect`. (#37)

### Changed
- **Breaking:** `dtype(df, col)` returns a `DataType` instead of a string. Compare with
  the constants (`== Int64`); `$` gives the old string. (#26)
- **Breaking:** `DataTypeKind` is a pure enum with Polars' names: `DataTypeKind.Int64`,
  `DataTypeKind.Other` instead of `dkInt64`, `dkOther`. (#28)

## [0.1.0] - 2026-10-28

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
- `nanuq/datasets` with `penguins()`, the Palmer penguins data (CC0) bundled for
  examples and tests. The README, the basic example, the tests and both dev-log posts
  use it instead of iris, and the iris sample is gone. The README links the posts. (#8)
- Prebuilt Polars wrapper libraries: `nimble install nanuq` (or Atlas, or a git clone)
  no longer needs Rust. At compile time `ffi.nim` downloads the static library for the
  platform from the `lib-v<version>` GitHub release (Linux x86_64 and arm64, macOS
  arm64, Windows x86_64 MinGW, plus `legacy-cpu` builds for x86_64 CPUs without
  AVX2), checks its SHA-256 against `src/nanuq/lib-sums.txt`, caches it, and falls
  back to cargo. Options `-d:nanuqLib=auto|prebuilt|source`, `-d:nanuqLegacyCpu`,
  `-d:nanuqCacheDir`, `-d:nanuqReleaseUrl`. The linked library's version is checked at
  startup. (#12)
- `release-lib.yml` builds, smoke-tests and publishes the six archives, from a
  `lib-v*` tag or from the Actions tab with "publish", and opens a PR with their sums.
  Releases so far: `lib-v0.1.0`, and `lib-v0.1.1` with `toHtml`. (#12, #13, #16)
- Dev-log index: the GitHub Pages root lists the posts, newest first, with date, title
  and summary, built from the rendered posts (`docs/index.nim`). (#20)
- `toHtml`: the HTML table Python Polars shows in notebooks (`_repr_html_`), with cells
  formatted by Polars; use it in nimib with `nbRawHtml: df.toHtml`. Needs lib 0.1.1. (#20)
- `nanuq/datamancer`: `toDatamancer` / `fromDatamancer` convert to and from Datamancer
  DataFrames, for example to plot with ggplotnim. Datamancer stays optional. (#20)

### Changed
- The Rust crate moved from `rust/` to `src/rust/`, so `nimble install` ships it. Release
  archives are built with fat LTO (22 MB instead of 44 MB gzipped). CI fails when
  `src/rust/` changes without a `-dev` version bump after a lib release. (#12)
- `toSeq` reads a whole column in one FFI call (two for strings) instead of one per
  cell. It now raises up front, naming the column, when the column has nulls; read it as
  `Option[T]` instead. `float` reads integer columns and `string` reads any column. (#5)
- CI builds the Rust library only when `rust/` changes, and shares it with the test and
  docs jobs. Dropped the unused Polars `dtype-full` feature, which cuts the static
  library from 400 to 300 MB. (#2)
- CI skips commits that only touch Markdown, `LICENSE`, `.gitignore`, `openspec/` or
  `.claude/`. (#3, #4)
