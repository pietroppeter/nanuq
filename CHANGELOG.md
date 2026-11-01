# Changelog

Notable changes to Nanuq. An entry is added when a change is implemented, usually when
its OpenSpec change is archived. Format based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

- Dev log post "Counting El Niños", the 0.4 explainer: what El Niño is, how NOAA counts
  it (ONI and the new RONI), and what it does to rain in Peru and to the world's
  temperature, using the 0.4 features on NOAA and NASA data. Every step and figure is
  shown in Nim (Nanuq, nim-plotly) and Python (py-polars, Plotly) tabs, and each Nim
  output is checked against the recorded Python one when the page is built.

## [0.4.0] - 2026-11-01

Nanuq 0.4 is "a real Series, and shaping": math, cumulative and rolling windows,
ranking and recoding, horizontal functions and correlation, pivot and unpivot, time
windows and as-of joins, a Series you can compute with, rows as Nim objects and
Arraymancer tensors. The dev log post "Designing Nanuq 0.4" explains the API choices.
The prebuilt library is `lib-v0.4.0` (Polars 0.55), with many more Polars features
turned on than 0.3.

Known limitations compared with Polars: no List, Array or Struct columns (so no
`explode`, `unnest`, `str.split`), no JSON, no Nim callbacks and no SQL.

### Added
- Dev log post "Designing Nanuq 0.4": the API choices of 0.4 where Nim and Polars
  disagree (optional parameters of several types, the Series as a layer over
  expressions, rows as objects), with code that runs. (#51)
- Math functions: `sqrt`, `cbrt`, `exp`, `log(base)`, `log10`, `log1p`, `sign`,
  `floor`, `ceil`, `clip` (both bounds, or one named), trigonometry (`sin` ... `arctanh`,
  `degrees`, `radians`, `arctan2`), `dot`, and NaN and infinity (`isNan`, `isFinite`,
  `isInfinite`, `fillNan`, `dropNans`, `Expr.dropNulls`). The wrapper crate is
  `0.4.0-dev`. (add-expr-math, #51)
- `shift` (with `fillValue`), `diff` (with `NullBehavior`), `pctChange`, cumulative
  functions (`cumSum`, `cumProd`, `cumMin`, `cumMax`, `cumCount`, with `reverse`),
  `rleId`, `peakMax`, `peakMin`, and the aggregations `product`, `mode`, `argMin`,
  `argMax`, `skew`, `kurtosis`. (add-cumulative-and-shift, #51)
- Rolling windows: `rollingSum`, `rollingMean`, `rollingMin`, `rollingMax`,
  `rollingMedian`, `rollingStd`, `rollingVar`, `rollingQuantile` over rows (with
  `weights`, `minSamples`, `center`) and their `By` variants over a time column
  (`rollingMeanBy("day", 7.days)`); `ewmMean`, `ewmStd`, `ewmVar`; `interpolate` and
  `interpolateBy`. (add-rolling-and-ewm, #51)
- Value functions: `Expr.sort`, `argSort`, `sortBy`, `reverse`, `head`, `tail`, `slice`,
  `gather`, `gatherEvery`, `topK`, `bottomK`, `topKBy`, `bottomKBy`, `indexOf`,
  `searchSorted`; `Expr.unique`, `isUnique`, `isDuplicated`, `isFirstDistinct`,
  `isLastDistinct`, `argUnique`, `uniqueCounts`, `approxNUnique`; `replace` and
  `replaceStrict` (with a mapping `{"a": "x"}`), `cut`, `qcut`; and `valueCounts` on
  frames. (add-value-functions, #51)
- Horizontal functions (`sumHorizontal`, `meanHorizontal`, `minHorizontal`,
  `maxHorizontal`, `allHorizontal`, `anyHorizontal`, `coalesce`), `intRange`,
  `linearSpace`, `repeat`, and `corr` (Pearson or Spearman) and `cov`.
  (add-horizontal-and-ranges, #51)
- Reshaping: `pivot` (with `PivotAgg` or an expression on `element()`), `unpivot`,
  `transpose`, `partitionBy`, `toDummies`; `Expr.item`. (add-reshaping, #51)
- Time-based grouping and as-of joins: `groupByDynamic` (with `every`, `period`,
  `offset`, `Label`, `StartBy`), the rolling group-by `rolling(indexColumn, period)`, and
  `joinAsof` (with `AsofStrategy`, `by`, `tolerance`). (add-dynamic-group-by, #51)
- A real Series: `df["col"]`, `getColumn`, `toSeries`; `name`, `len`, `dtype`,
  `nullCount`, `toList`, `item`, `toFrame`, `alias`; operators with literals and other
  Series, `filter`, and the expression methods (`s.max`, `s.rollingMean(3)`,
  `s.cut([0.0])`, ...) evaluated through expressions; `df.withColumns(series)` and
  `lit(series)`. (add-series-api, #51)
- `nanuq/arraymancer`, an optional module: `toTensor` for a Series, a column or a whole
  frame (2-D), and `toSeries`/`toDataFrame` from tensors. (add-arraymancer-interop, #51)
- Row objects: `df.rows(T)`, `df.iterRows(T)` and `df.row(i, T)` for Nim objects and
  named tuples, and `toDataFrame(seq[T])`. (add-row-objects, #51)
- Dev log post "Aged 19", the 0.3 explainer: Paul Seixas's 2026 season and 130 years
  of cycling's age and speed records, using every 0.3 feature on Wikipedia data. Each
  output is checked against the same steps in Python Polars when the page is built.

### Added (from the 0.4 explainer draft)
- Frame `topK(k, by, reverse)` and `bottomK`, eager and lazy, returning whole rows
  (Python's `df.top_k`). (#51)
- `date(year, month, day)` with expression parts builds a Date column (Polars' `date`). (#51)
- `setFloatPrecision(n)` and `floatPrecision` in `setConfig`/`withConfig` (Python's
  `float_precision`). (#51)

### Added (from the 0.4 book ports)
- `any` and `all` aggregations on boolean columns (`ignoreNulls`), also on Series. (#51)
- `lit(nil)` null literal and `fillNan(nil)` (Python's `pl.lit(None)`, `fill_nan(None)`). (#51)
- `groupBy("a", "b")` and `select("a", "b")` with column names. (#51)
- `gatherEvery(n, offset)` on frames. (#51)

### Changed
- **Breaking:** on a DataFrame, `groupBy`, `groupByDynamic` and `rolling` followed by
  `agg` return a DataFrame, as in Python (they returned a LazyFrame). A leftover
  `.collect` on a DataFrame is now a compile error with a hint, instead of being taken
  by std/sugar's `collect`. (#51)
- API conventions now also cover converter parameter types (`ColumnNames`, `OptInterval`,
  `JoinKey`, `AsofTolerance`) for parameters that take several types. (#51)
- **Breaking:** Python's `method` parameter is `how` in Nanuq (`method` is a Nim keyword):
  `rank(how = Dense)` (was `rankMethod`), `corr(a, b, how = Spearman)`,
  `interpolate(how = Nearest)`. The rule is in api-conventions. (#51)

## [0.3.0] - 2026-11-01

Nanuq 0.3 adds the data types and functions real tables need: dates, datetimes,
durations and times of day with the `dt` namespace, string functions with the `str`
namespace, categoricals (a Nim enum is a Polars Enum), Parquet and Arrow IPC, typed
errors, and `glimpse`/`describe`. The dev log post "Designing Nanuq 0.3" explains the
API choices. The prebuilt library is `lib-v0.3.0` (Polars 0.55), now built like
py-polars (nightly Rust, Polars' nightly feature, jemalloc): PDS-H runs about 4x faster
than with 0.2.

Known limitations compared with Polars: no List or Struct columns (so no `str.split`),
no `groupByDynamic` or rolling windows, no pivot, and no writing to streams.

### Added
- Runnable examples in the OpenSpec specs: every API requirement shows a Nim example and
  the table it prints, checked against the code by `nimble specexamples` in CI; specview
  shows them (add-spec-examples, #41, #43)
- `col.name` shorthand (`col.race` is `col("race")`, like Python's `pl.col.race`), a
  block syntax for `newDataFrame` (`name: [values]` lines, `nil` for missing values),
  `Expr.nullCount`, and `rank` with a `RankMethod` (`rank(Min, descending = true)`).
  The wrapper crate is `0.3.0-dev`. (add-api-polish, #47)
- `glimpse` (returns Python's one-line-per-column preview as a string), `describe`
  (summary statistics with `percentiles`), and display config: `setTblRows`,
  `setTblCols`, `setTblWidthChars`, `setFmtStrLengths`, `setConfig(...)`,
  `resetConfig()` and the scoped `withConfig(...): body`. (add-inspection-and-config, #47)
- String expressions: the `str` namespace (`lenChars`, `toUppercase`, `stripChars`,
  `startsWith`, `contains(pattern, literal)`, `extract`, `replace`, `replaceAll`,
  `slice`, `padStart`, `zfill`, the `join` aggregation, and more), plus `concatStr` and
  `format("{} ({})", ...)`. Patterns are Rust regexes. (add-string-expressions, #47)
- Temporal types: Date, Datetime (with time unit and time zone), Duration and Time
  columns, built from Nanuq's `Date` and `TimeOfDay` and std/times' `DateTime` and
  `Duration` (nanuq exports std/times); temporal casts and literals; `dateRange`,
  `datetimeRange` and `duration`; string parsing (`str.toDate`, `str.toDatetime`,
  `str.toTime`, `str.strptime`) and `tryParseDates` for CSV; the `dt` namespace with
  parts, formatting, truncation, offsets, time zones, `combine` and duration totals.
  (add-temporal-types, #47)
- Parquet and Arrow IPC: `scanParquet`, `readParquet`, `writeParquet` (with
  `ParquetCompression`, `compressionLevel`, `statistics`, `rowGroupSize`), `scanIpc`,
  `readIpc`, `writeIpc` (with `IpcCompression`), and reading CSV, Parquet and IPC from a
  Nim `Stream` (`readCsv(newStringStream(text))`). (add-parquet-ipc, #47)
- Categoricals: `Categorical` and `Enum(["low", "high"])` dtypes, and Nim enums as
  Polars Enums (`cast(Monument)`, `series("m", [Gold, Silver])`, `toList(df, "m",
  Medal)`, `col.medal == Gold`); the `cat` namespace (`getCategories`, `lenChars`,
  `startsWith`, `slice`, ...) and `Expr.toPhysical`. (add-categoricals, #47)
- `Expr.filter(predicate)` for conditional aggregations, and `col(names)` with a list or
  seq of names. (add-expr-filter, #47)
- `str.toTitlecase`, with the release libraries (it needs Polars' nightly feature).
  (build-lib-with-nightly, #47)
- specview shows every spec in full and hides archived changes behind a checkbox
  (except those changed since `--base`). (add-specview-full-specs, #47)

### Changed
- **Breaking:** `/` is true division, as in Python Polars and Nim: integer columns
  divide to f64, and a division by zero gives `inf` or `NaN`. `div` stays floor
  division. (add-api-polish, #47)
- **Breaking:** `NanuqError` is renamed `PolarsError`, with Python's subtypes
  (`ColumnNotFoundError`, `ComputeError`, `DuplicateError`, `InvalidOperationError`,
  `NoDataError`, `OutOfBoundsError`, `SchemaError`, `SchemaFieldNotFoundError`,
  `ShapeError`, `StructFieldNotFoundError`, `SqlError`) raised by Polars error kind
  (new `nq_last_error_kind` in the ABI). IO failures raise Nim's `IOError`.
  (add-typed-errors, #47)
- The prebuilt libraries are built with nightly Rust, Polars' `nightly` feature and
  jemalloc (crate features `nightly` and `jemalloc`, off for local builds), as py-polars
  is: PDS-H at scale factor 1 goes from 13.6 s to 3.2 s on an M3 Pro, within 5% of
  py-polars. (build-lib-with-nightly, #47)
- Data types cross the native ABI as an `NqDtypeSpec` struct (code, time unit, time
  zone, categories) instead of a single enum code. (add-temporal-types, #47)
- **Breaking:** `toSeq(df, column, T)` is renamed `toList` (Polars' `to_list`), so
  `sequtils.toSeq` works again with Nanuq imported. (add-api-polish, #47)

## [0.2.0] - 2026-10-31

Nanuq 0.2 covers what a first real analysis needs: data types and casts, joins and
concatenation, frame verbs, conditional and window expressions, column selectors, and
CSV options with lazy `scanCsv`. The dev log post "The great polar bear census" walks
through all of it. The prebuilt library is `lib-v0.2.0` (Polars 0.55).

Known limitations compared with Polars: no dates, datetimes or categoricals yet, no
string functions, and CSV is the only file format.

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
- Dev log post "The great polar bear census": every 0.2 feature on a season of messy
  ranger logs. Its outputs were computed with py-polars before 0.2 existed, and the
  page build now fails if Nanuq's outputs differ. (#38)

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
