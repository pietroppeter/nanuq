# Nanuq

> Watch out where the queries go, and process well that rusty data.

Nanuq (Inuit for "polar bear") brings [Polars](https://pola.rs) DataFrames to Nim.

> **Status: mostly feature complete, needs use and polish.** Nanuq 0.6.0 (2 November
> 2026) covers 115 of the 128 feature groups of Python Polars 2.1. What it needs now is
> real use and polishing, which is the likely focus of 0.7. The API can still change
> before 1.0.

```nim
import nanuq

type Size = enum cub, adult              # a Nim enum is a Polars Enum

let bears = newDataFrame:
  name: ["Nanuq", "Siku", "Ursa", "Kallik"]
  island: ["Svalbard", "Svalbard", "Wrangel", "Wrangel"]
  kg: [420, 95, 380, nil]                # nil is a missing value

let sized = bears.withColumns:
  choose(if col.kg < 150: cub else: adult).cast(Size).alias("size")
echo sized.lazy
  .dropNulls("kg")
  .groupBy("island")
  .agg(col.kg.mean, col.size.min)        # enum order: cub < adult
  .sort("island")
  .collect

for b in sized.rows(tuple[name: string, kg: Option[int]]):  # typed Nim values
  if b.kg.isNone: echo b.name, " skipped the weigh-in"
```

```
shape: (2, 3)
┌──────────┬───────┬───────┐
│ island   ┆ kg    ┆ size  │
│ ---      ┆ ---   ┆ ---   │
│ str      ┆ f64   ┆ enum  │
╞══════════╪═══════╪═══════╡
│ Svalbard ┆ 257.5 ┆ cub   │
│ Wrangel  ┆ 380.0 ┆ adult │
└──────────┴───────┴───────┘
Kallik skipped the weigh-in
```

Queries read like Python Polars, with the same names in camelCase and `col.kg` for a
column. Where Nim helps:

- a frame is a block of `name: [values]` lines, with `nil` for a missing value;
- `choose` writes `when/then/otherwise` as a plain `if`/`else`;
- a Nim enum is a Polars Enum, so `cub` sorts before `adult` (as strings, `"adult"`
  would come first);
- results come back as typed Nim values (`rows`, `toList`, `df["kg", 0, int]`), with
  `Option` where a value can be missing.

`nanuq/datasets` bundles the [Palmer penguins](https://allisonhorst.github.io/palmerpenguins/)
data (CC0) for examples and tests.

For web pages, `df.toHtml` gives the HTML table Python Polars shows in Jupyter. In
[nimib](https://github.com/pietroppeter/nimib), `nbShow df` renders it.

Optional modules, each imported on its own so the core has no extra dependencies:

- `nanuq/datamancer` converts to and from [Datamancer](https://github.com/SciNim/Datamancer)
  DataFrames (`toDatamancer`, `fromDatamancer`), for example to plot with ggplotnim
  (needs `nimble install datamancer`).
- `nanuq/arraymancer` converts to and from Arraymancer tensors (`df.toTensor(float)`).
- `nanuq/database` reads and writes SQLite with `readDatabase` and `writeDatabase`
  (needs `nimble install db_connector`).
- `nanuq/testing` has Polars' test assertions (`assertFrameEqual`, `assertSeriesEqual`).

## What Nanuq covers

The [Polars coverage map](https://pietroppeter.github.io/nanuq/polars_coverage.html)
lists every Polars feature group and its status in the latest release (data in
[`docs/coverage/polars.json`](docs/coverage/polars.json)). In 0.6.0, 115 of 128 groups
are done: building and inspecting frames, expressions, every column type (strings,
dates and times, categoricals and enums, lists, structs, binary, decimal), lazy queries
with the streaming engine and sinks, joins, reshaping, rolling and time windows, SQL,
Nim callbacks, CSV, Parquet, IPC, JSON, Excel and cloud storage, and the Arrow C Data
Interface.

What is not there yet:

| Feature | Status | Note |
|---|---|---|
| Plotting | partial | No `df.plot` namespace. Plot with nim-plotly or ggplotnim through `toSeq` or `toDatamancer`. |
| Databases | partial | SQLite only (`nanuq/database`); PostgreSQL and MySQL to follow. |
| Library size and distribution | partial | One static library of about 286 MB (53 MB download); no shared library or per-area builds. |
| Combining | partial | `concat` has no `align`. |
| Apply and iterate, UDFs | partial | No `mapRows` and no `LazyFrame.mapBatches`. |
| Avro | missing | Not started. |

Some Polars features have no place in Nim and are not planned: `Object` columns
(Python objects), Delta Lake, Iceberg and catalogs (Python-only), expression plugins
(a Rust mechanism), the GPU engine (cuDF), and formula-style sugar (Polars expressions
already read well).

## Documentation

The development log, written with [nimib](https://github.com/pietroppeter/nimib)
(`docs/blog/`), is published at <https://pietroppeter.github.io/nanuq/>. Its
[index](https://pietroppeter.github.io/nanuq/) lists the posts newest first, and each
post links to the previous and next ones, to related posts and to its source:

- [Move 37](https://pietroppeter.github.io/nanuq/blog/2026-11-02-move-37.html) (2 November 2026)
- [Designing Nanuq 0.6](https://pietroppeter.github.io/nanuq/blog/2026-11-01-designing-0-6.html) (1 November 2026)
- [Above 4000](https://pietroppeter.github.io/nanuq/blog/2026-11-01-above-4000.html) (1 November 2026)
- [Designing Nanuq 0.5](https://pietroppeter.github.io/nanuq/blog/2026-11-01-designing-0-5.html) (1 November 2026)
- [Counting El Niños](https://pietroppeter.github.io/nanuq/blog/2026-11-01-counting-el-ninos.html) (1 November 2026)
- [Designing Nanuq 0.4](https://pietroppeter.github.io/nanuq/blog/2026-11-01-designing-0-4.html) (1 November 2026)
- [Aged 19](https://pietroppeter.github.io/nanuq/blog/2026-11-01-aged-19.html) (1 November 2026)
- [Designing Nanuq 0.3](https://pietroppeter.github.io/nanuq/blog/2026-10-31-designing-0-3.html) (31 October 2026)
- [Designing Nanuq 0.2](https://pietroppeter.github.io/nanuq/blog/2026-10-31-designing-0-2.html) (31 October 2026)
- [The great polar bear census](https://pietroppeter.github.io/nanuq/blog/2026-10-31-bear-census.html) (31 October 2026)
- [Shipping the Rust half](https://pietroppeter.github.io/nanuq/blog/2026-10-27-shipping-rust-binaries.html) (27 October 2026)
- [Plotting with ggplotnim](https://pietroppeter.github.io/nanuq/blog/2026-10-27-plotting-with-ggplotnim.html) (27 October 2026)
- [How Nanuq works](https://pietroppeter.github.io/nanuq/blog/2026-10-27-how-nanuq-works.html) (27 October 2026)

Next to the posts, the [Polars coverage map](https://pietroppeter.github.io/nanuq/polars_coverage.html)
lists every Polars feature group and its status in the latest release, and the
[OpenSpec page](https://pietroppeter.github.io/nanuq/openspec.html) shows the specs and
changes.

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

## How development works

- **Ideas** for future development are collected in [BACKLOG.md](BACKLOG.md). It is a
  loose list, not a roadmap.
- **Changes** are planned with [OpenSpec](https://github.com/Fission-AI/OpenSpec).
  `openspec/specs/` describes how Nanuq behaves today; the
  [OpenSpec page](https://pietroppeter.github.io/nanuq/openspec.html) on the site shows
  every spec and every change, rebuilt on each merge. Each change gets a proposal (with
  a "Differences from Polars" section), spec deltas, a design and tasks under
  `openspec/changes/`, and is archived into the specs once implemented. With Claude Code,
  use `/opsx:propose`, `/opsx:apply` and `/opsx:archive`; with another tool, the
  `openspec` CLI (`npm i -g @fission-ai/openspec`).
- **Specs are tested**: every API requirement has a Nim example with the full Polars
  output, and the test suite (`tests/test_specs*.nim`) checks that it still prints that.
- **Reviewing changes**: `nimble specview` writes `specview.html`, a page showing where
  each change is in the process, its proposal and tasks, its spec deltas (MODIFIED
  requirements as word diffs against the current spec) and the changed files. On PRs
  that touch `openspec/` or `BACKLOG.md`, CI posts a summary on the run page and
  attaches the full page as the `specview` artifact. The same report, without the
  diffs, is the site's OpenSpec page.
- **History**: each implemented change adds a line to [CHANGELOG.md](CHANGELOG.md), and
  each minor release gets a design post and a playful explainer in the dev log.
- **Releases**: the release PR bumps the version, writes the release notes and
  refreshes the coverage map. Once it is merged, the "Release lib" workflow builds and
  publishes the prebuilt libraries (`lib-v*`), their checksums land in
  `src/nanuq/lib-sums.txt`, and the release is tagged.
- **CI** skips changes that only touch Markdown, `openspec/` or `.claude/` (on `main`,
  `openspec/` changes still run it, to rebuild the OpenSpec page), and rebuilds the Rust
  library only when `src/rust/` changes.

## Install

```sh
nimble install https://github.com/pietroppeter/nanuq
```

Nanuq is not in the Nimble package list yet; once it is, `nimble install nanuq` (or
`atlas use nanuq`) will do.

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
nimble test       # runs the tests and the spec examples, as one program (tests/all.nim)
nimble example    # runs examples/basic.nim
nimble docs       # renders the site with nimib, as one program (docs/all.nim)
nim r tests/test_csv.nim       # one test file
nim r docs/blog/move_37.nim    # one post
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
