# Nanuq

> Watch out where the queries go, and process well that rusty data.

Nanuq (Inuit for "polar bear") brings [Polars](https://pola.rs) DataFrames to Nim.

> **Status: proof of concept.** The API is small and will change.

```nim
import nanuq, nanuq/datasets

echo penguins().lazy
  .dropNulls("body_mass_g")
  .groupBy(col("species"))
  .agg(col("body_mass_g").mean.alias("mean_body_mass_g"),
       col("species").count.alias("n"))
  .sort("mean_body_mass_g", descending = true)
  .collect
```

```
shape: (3, 3)
┌───────────┬──────────────────┬─────┐
│ species   ┆ mean_body_mass_g ┆ n   │
│ ---       ┆ ---              ┆ --- │
│ str       ┆ f64              ┆ u32 │
╞═══════════╪══════════════════╪═════╡
│ Gentoo    ┆ 5076.01626       ┆ 123 │
│ Chinstrap ┆ 3733.088235      ┆ 68  │
│ Adelie    ┆ 3700.662252      ┆ 151 │
└───────────┴──────────────────┴─────┘
```

`nanuq/datasets` bundles the [Palmer penguins](https://allisonhorst.github.io/palmerpenguins/)
data (CC0) for examples and tests.

For web pages, `df.toHtml` gives the HTML table Python Polars shows in Jupyter (in
nimib: `nbRawHtml: df.toHtml`). The optional module `nanuq/datamancer` converts to and
from [Datamancer](https://github.com/SciNim/Datamancer) DataFrames (`toDatamancer`,
`fromDatamancer`), for example to plot with ggplotnim; it needs `nimble install datamancer`.

## Documentation

The development log, written with [nimib](https://github.com/pietroppeter/nimib)
(`docs/blog/`), is published at <https://pietroppeter.github.io/nanuq/>, which lists
the posts newest first:

- [Designing Nanuq 0.5](https://pietroppeter.github.io/nanuq/blog/2026-11-01-designing-0-5.html) (1 November 2026)
- [Designing Nanuq 0.4](https://pietroppeter.github.io/nanuq/blog/2026-11-01-designing-0-4.html) (1 November 2026)
- [Aged 19](https://pietroppeter.github.io/nanuq/blog/2026-11-01-aged-19.html) (1 November 2026)
- [Designing Nanuq 0.3](https://pietroppeter.github.io/nanuq/blog/2026-10-31-designing-0-3.html) (31 October 2026)
- [Designing Nanuq 0.2](https://pietroppeter.github.io/nanuq/blog/2026-10-31-designing-0-2.html) (31 October 2026)
- [The great polar bear census](https://pietroppeter.github.io/nanuq/blog/2026-10-31-bear-census.html) (31 October 2026)
- [How Nanuq works](https://pietroppeter.github.io/nanuq/blog/2026-10-27-how-nanuq-works.html) (27 October 2026)
- [Plotting with ggplotnim](https://pietroppeter.github.io/nanuq/blog/2026-10-27-plotting-with-ggplotnim.html) (27 October 2026)
- [Shipping the Rust half](https://pietroppeter.github.io/nanuq/blog/2026-10-27-shipping-rust-binaries.html) (27 October 2026)

[The Nanuq Book](https://pietroppeter.github.io/nanuq-book/)
([source](https://github.com/pietroppeter/nanuq-book)) ports public Polars tutorials to
Nanuq, starting with chapters of the Polars user guide. Every chapter runs when the book
is built, and each one names its source and licence.

Official documentation will come later.

## How it works

Rust can export a C-compatible API, and Nim can call it like any C library.

```
Nim code ──► src/nanuq.nim      high level API: DataFrame, LazyFrame, Expr (refs with destructors)
             src/nanuq/ffi.nim  raw importc bindings, nbindgen style
                  │  C ABI
                  ▼
             src/rust/          nanuq_ffi crate: extern "C" functions over Polars,
                                built by cargo as a static library and linked in
```

- Polars objects live on the Rust heap and cross the boundary as opaque
  pointers. The Nim wrappers free them in `=destroy`.
- FFI functions borrow their arguments and return new objects (cloning is cheap
  in Polars), so Nim values can be shared freely.
- Errors and Rust panics are caught on the Rust side and re-raised in Nim as
  `PolarsError` (typed as in Python: `ColumnNotFoundError`, `InvalidOperationError`, ...), or Nim's `IOError` for IO.

## How we work

- **Ideas** go in [BACKLOG.md](BACKLOG.md). When an idea has been implemented, it moves
  from the backlog to [CHANGELOG.md](CHANGELOG.md).
- **Changes** are planned with [OpenSpec](https://github.com/Fission-AI/OpenSpec).
  `openspec/specs/` describes how Nanuq behaves today, and each change gets a proposal,
  spec deltas, a design and tasks under `openspec/changes/`. With Claude Code, use
  `/opsx:propose`, `/opsx:apply` and `/opsx:archive`. With another tool, use the
  `openspec` CLI (`npm i -g @fission-ai/openspec`).
- **Reviewing changes**: `nimble specview` writes `specview.html`, a page showing where
  each change is in the process, its proposal and tasks, its spec deltas (MODIFIED
  requirements as word diffs against the current spec) and the changed files. On PRs
  that touch `openspec/` or `BACKLOG.md`, CI posts a summary on the run page and
  attaches the full page as the `specview` artifact.
- Changes that only touch Markdown, `openspec/` or `.claude/` don't trigger the main CI.

## Install

```sh
nimble install nanuq                                # or: atlas use nanuq
nimble install https://github.com/pietroppeter/nanuq  # before it is in the package list
```

Requirements: Nim >= 2.0, plus `curl` and `tar` (included in Windows 10+, macOS and
most Linux distributions).

Nanuq links a static library, `libnanuq_ffi.a`, that wraps Polars. The first time you
compile a program that imports `nanuq`, the library for your platform is downloaded from
the project's GitHub releases, checked against the SHA-256 in
`src/nanuq/lib-sums.txt`, and cached for later compiles:

| Platform | Prebuilt library |
|---|---|
| Linux x86_64 and arm64 (glibc 2.28+) | yes |
| macOS arm64 (11+) | yes |
| Windows x86_64 (Nim's default MinGW compiler) | yes |
| anything else | built from source with cargo, Polars included (needs Rust) |

On x86_64 there is a build for CPUs with AVX2 and FMA (most from 2013 on) and a
`legacy-cpu` build for older ones. Linux picks automatically; elsewhere pass
`-d:nanuqLegacyCpu` for an older CPU, or when the program will run on older machines
than the one compiling it.

Compile-time options:

- `-d:nanuqLib=source` never downloads and builds with cargo (needs
  [Rust](https://rustup.rs)). `-d:nanuqLib=prebuilt` (or `-d:nanuqNoCargo`) never
  runs cargo. The default, `auto`, downloads and falls back to cargo.
- `-d:nanuqLibDir=<dir>` links `<dir>/libnanuq_ffi.a`, for example an archive you
  downloaded by hand from the releases page.
- `-d:nanuqCacheDir=<dir>` moves the cache (default: `~/.cache/nanuq`,
  `~/Library/Caches/nanuq` on macOS, `%LOCALAPPDATA%\nanuq` on Windows).
- `-d:nanuqReleaseUrl=<url>` downloads from a mirror of the GitHub releases, for
  example behind a corporate proxy. The checksums still apply.

## Try it from a clone

A clone uses the same prebuilt library as an installed package, so it needs no Rust:

```sh
nimble test       # runs the tests
nimble example    # runs examples/basic.nim
nimble docs       # renders the dev log posts in docs/blog with nimib
```

Changing the Rust wrapper in `src/rust/` needs a Rust toolchain (`cargo`, stable):

```sh
nimble buildRust  # builds src/rust/target/release/libnanuq_ffi.a (compiles Polars too)
```

Once that file exists it is linked instead of the download, so run `nimble buildRust`
again after each change to `src/rust/`, and delete the file to go back to the prebuilt
library. Bump the crate version to a `-dev` version when you change it (CI checks this).

A stable build is several times slower than the prebuilt library, which is built like
py-polars: with nightly Rust, Polars' `nightly` feature and jemalloc. To get the same
speed locally, build with `cargo +nightly-2026-04-01 build --release --features
"nightly jemalloc" --manifest-path src/rust/Cargo.toml` (`str.toTitlecase` also needs
the `nightly` feature).

## What is there

- Build: `newDataFrame(series("a", [1, 2, 3]), series("b", ["x", "y", "z"]))`, or a
  block with one `name: [values]` line per column (`nil` is a missing value, names that
  aren't identifiers are strings), `readCsv`, `writeCsv`
- CSV: `scanCsv("logs/*.csv")` reads lazily, globs included (same columns in every
  file). `readCsv` (which is `scanCsv(...).collect`) takes the same named options with
  Polars' defaults: `separator = ';'`, `hasHeader`, `nullValues = ["NA"]`,
  `schemaOverrides = {"bears": Int64}`, `skipRows`, `nRows`, `columns`,
  `inferSchemaLength` (`none(int)` for all rows), `ignoreErrors`, `decimalComma`.
  `writeCsv` takes `separator`, `includeHeader`, `nullValue`,
  `quoteStyle` (`QuoteStyle.Always`, ...), `floatPrecision` and `decimalComma`
- Parquet and Arrow IPC: `scanParquet`, `readParquet(path, columns = [...], nRows = 10)`,
  `writeParquet(path, compression = ParquetCompression.Zstd, compressionLevel = 19)`,
  and the same for IPC (`scanIpc`, `readIpc`, `writeIpc`). `readCsv`, `readParquet` and
  `readIpc` also read a Nim `Stream` (`readCsv(newStringStream(text))`)
- Inspect: `$df`, `shape`, `columns`, `dtype`, `head`, `df["col", row, float]`,
  `toList(df, "col", float)` (one FFI call per column), `echo df.glimpse` (one line per
  column), `describe` (summary statistics)
- Display: `setTblRows(20); setTblCols(10)` (also `setTblWidthChars`, `setFmtStrLengths`,
  `setFloatPrecision`), `setConfig(tblRows = 20, floatPrecision = 2)`, `resetConfig()`, and for one block
  `withConfig(tblRows = 40): echo df`
- Missing values: read as `Option[T]` (`toList(df, "col", Option[int])`,
  `df["col", row, Option[string]]`), `nullCount`, `hasNulls`,
  `series("a", [some(1), none(int)])`, `readCsv(path, nullValues = ["NA"])`,
  and in queries `isNull`, `isNotNull`, `fillNull`, `dropNulls`. Plain `toList(df, "col", int)`
  raises on a column with nulls.
- Data types: `dtype(df, "col") == Int64` (constants named as in Polars, `$` gives
  `"i64"`), `dtypes`, `schema`, `lf.collectSchema`, and `cast` with a Nim type
  (`col("a").cast(int32)`, `df.cast(float64)`) or per column (`df.cast({"a": Int32})`),
  strict by default (`strict = false` turns failures into nulls)
- Expressions: `col("a")` or `col.a`, `lit`, `+ - * / mod div ^`, unary `-`, `abs`,
  `round`, comparisons, `and or not`, `isIn`, `isBetween`, `sum mean median min max count
  len first last nUnique std var quantile nullCount`, `rank(Min, descending = true)`, `alias`,
  `filter` inside an aggregation (`col.pts.filter(col.kind == "TT").sum`)
- Strings: `col.race.str.replaceAll("–", "-", literal = true)`, `str.contains`,
  `str.extract(r"(\d+)'")`, `str.toUppercase`, `str.stripChars`, `str.slice`,
  `str.zfill`, `str.join(", ")` in `agg`, `format("{} ({})", col.rider, col.nat)`,
  `concatStr`
- Dates and times: `Date` (`date(2026, 7, 4)`), `TimeOfDay` (`timeOfDay(13, 10)`) and
  std/times' `DateTime` and `Duration` as column values and literals; `cast(Date)`,
  `cast(DateTime, timeUnit = Milliseconds, timeZone = "Europe/Rome")`; parsing with
  `str.toDate("%d %B %Y")`, `str.toDatetime`, `str.strptime(T, fmt)` and
  `readCsv(path, tryParseDates = true)`; `dateRange(a, b, 1.months)`, `date(col.year, col.month, 15)`, `datetimeRange`,
  `duration(hours = col.h)`; the `dt` namespace (`dt.year`, `dt.weekday`, `dt.date`,
  `dt.toString(fmt)`, `dt.truncate`, `dt.offsetBy(19.years)`, `dt.convertTimeZone`,
  `dt.replaceTimeZone`, `dt.combine`, `dt.totalDays`, ...). DateTime values are stored
  and read back as UTC instants
- Categoricals: a Nim enum is a Polars Enum (`col.race.cast(Monument)` sorts races in
  enum order, `toList(df, "race", Monument)`, `col.race == Roubaix`), `Enum(["low",
  "high"])` at run time, `cast(Categorical)`, and `cat.getCategories`
- Conditionals: `` `when`(cond).then(a).otherwise(b) ``, or the `choose` macro over
  `if`/`elif`/`else` (strings in branches are values, not column names)
- Column selectors: `col(SomeNumber)` (and `SomeInteger`, `SomeFloat`, ...), `col(int)`,
  `col(float, string)`, `col("a", "b")`, `col(someSeq)`, `all()`, regex `col("^w.*$")`, `.exclude("id")`,
  used like any expression (`agg(col(SomeNumber).mean.name.suffix("_mean"))`)
- Fill and windows: `fillNull(Forward)`, `forwardFill`, `backwardFill`, `fillNull(Mean)`,
  and `over("group")` for per-group values on every row
- Lazy queries: `lazy`, `select`, `withColumns`, `filter`, `groupBy(...).agg(...)`, `sort`, `limit`, `collect`, `explain`
  (on a DataFrame, `df.groupBy("species").agg(...)` returns a DataFrame directly)
  (eager shortcuts exist on `DataFrame` for `select`, `withColumns`, `filter`, `sort`)
- Frame verbs (lazy and eager): `drop("a")` or `drop(["a", "b"])`, `rename({"old": "new"})`,
  `head`, `tail`, `slice(offset, length)`, `reverse`, `withRowIndex`,
  `unique("k", keep = First)`, and sorting by several keys
  (`sort(["g", "v"], descending = [false, true], nullsLast = [true])`). On DataFrame:
  `sample(3, seed = 42)` or `sample(fraction = 0.1)`, and `setRandomSeed(42)`
- Joins: `a.join(b, on = ["id"], how = Left)`, `leftOn`/`rightOn` (names or expressions),
  `a.join(b, how = Cross)`, with `suffix`, `validate`, `nullsEqual`, `coalesce` and
  `maintainOrder`. As in Polars, the row order of a join is not guaranteed unless you
  pass `maintainOrder`
- Concatenation: `concat([a, b])`, with `how = VerticalRelaxed`, `Horizontal`, `Diagonal`
  or `DiagonalRelaxed`
- Math: `sqrt`, `exp`, `log(2.0)`, `log10`, `sign`, `floor`, `ceil`,
  `clip(-1.0, 1.0)` (or `clip(lowerBound = 0)`), trigonometry, `dot`, and NaN
  (`isNan`, `fillNan`, `dropNans`), which stays distinct from null
- Rows before and after: `shift(1, fillValue = 0)`, `diff`, `pctChange`, `cumSum`,
  `cumMax`, `rleId` (runs of equal values), `peakMax`; rolling windows over rows
  (`rollingMean(3, center = true)`) or time (`rollingSumBy("day", 7.days)`),
  `ewmMean(span = 12)`, `interpolate`
- Values of a column: `sort`, `sortBy`, `topK`, `topKBy("score", k = 3)`, `gather`,
  `unique`, `isDuplicated`, `replace({"N": "north"})`, `replaceStrict(..., default = ...)`,
  `cut([-0.5, 0.5], labels = [...])`, `qcut(4)`, `df.valueCounts("col", sort = true)`, and
  whole rows with `df.topK(5, by = "peak")` / `bottomK`
- Across a row: `sumHorizontal(col(float))`, `maxHorizontal("a", "b")`,
  `anyHorizontal`, `coalesce`; generated columns `intRange`, `linearSpace`, `repeat`;
  `corr("a", "b", Spearman)`, `cov`
- Reshaping: `pivot("season", index = "year", values = "oni")` (with `PivotAgg.Sum` or an
  expression on `element()`), `unpivot(index = "year")`, `transpose`, `partitionBy`,
  `toDummies`
- Time windows: `groupByDynamic("day", every = 1.months).agg(...)`, the rolling group-by
  `rolling("day", period = 7.days)`, and `joinAsof(other, leftOn = "t", rightOn = "day",
  by = "site", tolerance = 1.days)`
- Series: `df["oni"]`, `s.max.item(float)`, `s * 2`, `s.filter(s > 0)`,
  `s.rollingMean(3)` (every expression method works on a Series), `df.withColumns(s)`
- Rows as objects: `df.rows(Reading)`, `for r in df.iterRows(tuple[a: int, b: string])`,
  `seqOfObjects.toDataFrame`
- Arraymancer (optional, `import nanuq/arraymancer`): `df.toTensor(float)`,
  `tensor.toDataFrame(["a", "b"])`

## Conventions

- Names follow Polars, in camelCase: `withColumns`, `groupBy`, `nullCount`.
- Option values that come from a closed set are pure enums named after Rust Polars'
  types and variants: `JoinType.Left`, `MaintainOrderJoin.Left`, `ConcatMethod.Diagonal`
  (where Rust has no enum, the name follows Python's strings). There are no string options.
- Where Nim knows the expected type, write the bare value: `how = Left, maintainOrder = Left`.
  Elsewhere qualify it (`let h = JoinType.Left`), since several enums share value names.
- Python's `method` parameter (a Nim keyword) is `how`: `rank(how = Dense)`, `corr(a, b, how = Spearman)`.
- A parameter that takes several types uses a small converter type (`ColumnNames`,
  `OptInterval`, `JoinKey`, `AsofTolerance`), so `pivot("m", index = "year")` and
  `index = ["year", "month"]` both work.
- Operators keep Polars' meaning, not Nim's: `mod` and `div` round towards negative
  infinity (`-7 mod 3 == 2`), and `round` breaks ties to the even digit. `/` is true
  division (`7 / 2 == 3.5`), as in Python Polars and in Nim.
- Polars names that are Nim keywords work after a dot (`e.cast(Int32)`, `e.var`,
  `.when(c)`); as a first call they need backticks (`` `when`(c) ``).

## Next steps

See [BACKLOG.md](BACKLOG.md).
