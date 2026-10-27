# Nanuq

*Watch out where the huskies go, and don't you eat that rusty data.*

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

## Documentation

The development log, written with [nimib](https://github.com/pietroppeter/nimib)
(`docs/blog/`), is published at <https://pietroppeter.github.io/nanuq/>:

- [How Nanuq works](https://pietroppeter.github.io/nanuq/blog/2026-10-27-how-nanuq-works.html) (27 October 2026)
- [Plotting with ggplotnim](https://pietroppeter.github.io/nanuq/blog/2026-10-27-plotting-with-ggplotnim.html) (27 October 2026)

Official documentation will come later.

## How it works

Rust can export a C-compatible API, and Nim can call it like any C library.

```
Nim code ──► src/nanuq.nim      high level API: DataFrame, LazyFrame, Expr (refs with destructors)
             src/nanuq/ffi.nim  raw importc bindings, nbindgen style
                  │  C ABI
                  ▼
             rust/              nanuq_ffi crate: extern "C" functions over Polars,
                                built by cargo as a static library and linked in
```

- Polars objects live on the Rust heap and cross the boundary as opaque
  pointers. The Nim wrappers free them in `=destroy`.
- FFI functions borrow their arguments and return new objects (cloning is cheap
  in Polars), so Nim values can be shared freely.
- Errors and Rust panics are caught on the Rust side and re-raised in Nim as
  `NanuqError`.

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

## Requirements

- Nim >= 2.0
- A Rust toolchain (`cargo`), stable

## Try it

```sh
nimble test       # builds the Rust library, then runs the tests
nimble example    # runs examples/basic.nim
nimble docs       # renders the dev log posts in docs/blog with nimib
```

The first build compiles Polars and takes a few minutes. If the static library
is missing, importing `nanuq` also runs `cargo build` at compile time
(disable with `-d:nanuqNoCargo`, or point to a prebuilt library with
`-d:nanuqLibDir=...`).

## What is there

- Build: `newDataFrame(series("a", [1, 2, 3]), series("b", ["x", "y", "z"]))`, `readCsv`, `writeCsv`
- Inspect: `$df`, `shape`, `columns`, `dtype`, `head`, `df["col", row, float]`,
  `toSeq(df, "col", float)` (one FFI call per column)
- Missing values: read as `Option[T]` (`toSeq(df, "col", Option[int])`,
  `df["col", row, Option[string]]`), `nullCount`, `hasNulls`,
  `series("a", [some(1), none(int)])`, `readCsv(path, nullValues = ["NA"])`,
  and in queries `isNull`, `isNotNull`, `fillNull`, `dropNulls`. Plain `toSeq(df, "col", int)`
  raises on a column with nulls.
- Expressions: `col`, `lit`, `+ - * /`, comparisons, `and or not`, `sum mean min max count first last nUnique std`, `alias`
- Lazy queries: `lazy`, `select`, `withColumns`, `filter`, `groupBy(...).agg(...)`, `sort`, `limit`, `collect`, `explain`
  (eager shortcuts exist on `DataFrame` for `select`, `withColumns`, `filter`, `sort`)

## Next steps

See [BACKLOG.md](BACKLOG.md).
