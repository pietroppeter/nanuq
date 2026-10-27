# Nanuq

*Watch out where the huskies go, and don't you eat that rusty data.*

Nanuq (Inuit for "polar bear") brings [Polars](https://pola.rs) DataFrames to Nim.

> **Status: proof of concept.** The API is small and will change.

```nim
import nanuq

let iris = readCsv("examples/iris_sample.csv")
echo iris.lazy
  .filter(col("sepal_length") > 5.0)
  .groupBy(col("species"))
  .agg(col("sepal_length").mean.alias("mean_sepal_length"),
       col("species").count.alias("n"))
  .sort("mean_sepal_length", descending = true)
  .collect
```

## How it works

This follows the approach discussed in the Nim forum thread
[nbindgen - calling rust code from nim](https://forum.nim-lang.org/t/5816#57150):
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

## Documentation

A walkthrough of how Nanuq works, written with [nimib](https://github.com/pietroppeter/nimib)
(`docs/walkthrough.nim`), is published at <https://pietroppeter.github.io/nanuq/>.

## Requirements

- Nim >= 2.0
- A Rust toolchain (`cargo`), stable

## Try it

```sh
nimble test       # builds the Rust library, then runs the tests
nimble example    # runs examples/basic.nim
nimble docs       # renders docs/walkthrough.nim with nimib
```

The first build compiles Polars and takes a few minutes. If the static library
is missing, importing `nanuq` also runs `cargo build` at compile time
(disable with `-d:nanuqNoCargo`, or point to a prebuilt library with
`-d:nanuqLibDir=...`).

## What is there

- Build: `newDataFrame(series("a", [1, 2, 3]), series("b", ["x", "y", "z"]))`, `readCsv`, `writeCsv`
- Inspect: `$df`, `shape`, `columns`, `dtype`, `head`, `df["col", row, float]`, `toSeq`
- Expressions: `col`, `lit`, `+ - * /`, comparisons, `and or not`, `sum mean min max count first last nUnique std`, `alias`
- Lazy queries: `lazy`, `select`, `withColumns`, `filter`, `groupBy(...).agg(...)`, `sort`, `limit`, `collect`, `explain`
  (eager shortcuts exist on `DataFrame` for `select`, `withColumns`, `filter`, `sort`)

## Next steps

- Generate `src/nanuq/ffi.nim` with [nbindgen](https://github.com/arnetheduck/nbindgen) instead of by hand
- Zero-copy column exchange through the Arrow C Data Interface
- More IO (Parquet, scan_csv), joins, more dtypes (dates, nulls)
- Prebuilt libraries so users don't need cargo; `nimble install` support
