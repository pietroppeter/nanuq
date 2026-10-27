import nimib
import std/[os, strutils]
import nanuq

nbInit
nb.title = "How Nanuq works"

nbText: """
# How Nanuq works

> *Watch out where the huskies go, and don't you eat that rusty data.*

**Nanuq** (Inuit for *polar bear*) brings [Polars](https://pola.rs) DataFrames to Nim.
This page is a [nimib](https://github.com/pietroppeter/nimib) document. Every Nim
block below was run when the page was built, and its output is shown underneath.

The idea comes from the Nim forum thread
[nbindgen, calling rust code from nim](https://forum.nim-lang.org/t/5816#57150):
Rust can export a C-compatible API, and Nim can call that API as easily as any C
library. No GC or runtime has to be shared, only plain functions and pointers.

## The three layers

```
your Nim code
   │
   ▼
src/nanuq.nim        DataFrame, LazyFrame, Expr: Nim refs with destructors
src/nanuq/ffi.nim    raw `importc` declarations, one per Rust function
   │   C ABI (extern "C", opaque pointers)
   ▼
rust/src/lib.rs      nanuq_ffi crate: thin functions over Polars,
                     compiled by cargo into libnanuq_ffi.a and linked in
```

### 1. Rust: export a C ABI over Polars

Polars objects never cross the boundary by value. Each one is boxed on the Rust heap,
and Nim only holds a pointer to it. Every function is wrapped in `guard`, which turns
both `Err` results and panics into a NULL return plus an error message. Unwinding
into Nim would be undefined behaviour, so this matters.

```rust
#[no_mangle]
pub unsafe extern "C" fn nq_df_read_csv(path: *const c_char) -> *mut DataFrame {
    boxed(guard(|| {
        let path = PathBuf::from(cstr(path)?);
        CsvReadOptions::default()
            .with_has_header(true)
            .try_into_reader_with_file_path(Some(path))
            .map_err(pe)?
            .finish()
            .map_err(pe)
    }))
}

#[no_mangle]
pub unsafe extern "C" fn nq_lf_filter(lf_: *const LazyFrame, predicate: *const Expr) -> *mut LazyFrame {
    boxed(guard(|| Ok(lf(lf_)?.filter(borrow(predicate, "expression")?.clone()))))
}
```

Functions **borrow** their arguments and return **new** objects. Cloning is cheap in
Polars (columns are reference counted and a lazy plan is a tree of `Arc`s), and it
keeps ownership simple: whoever got a pointer frees it, exactly once.

### 2. Nim: declare the functions

`ffi.nim` mirrors the C ABI one to one, the way an
[nbindgen](https://github.com/arnetheduck/nbindgen) generated file would. It also
links the static library, and runs `cargo build` at compile time if the library
is missing.

```nim
type
  NqDataFrame* {.incompleteStruct.} = object   # opaque: Nim never looks inside
  NqLazyFrame* {.incompleteStruct.} = object
  NqExpr* {.incompleteStruct.} = object

{.push importc, cdecl.}
proc nq_df_read_csv*(path: cstring): ptr NqDataFrame
proc nq_lf_filter*(lf: ptr NqLazyFrame, predicate: ptr NqExpr): ptr NqLazyFrame
proc nq_df_free*(df: ptr NqDataFrame)
{.pop.}
```

### 3. Nim: make it feel like Nim

`nanuq.nim` wraps each pointer in a `ref` object whose `=destroy` hook calls the
matching `*_free`. Because Polars values are immutable from Nim's side, sharing a
ref is safe, and the Rust object goes away when the last ref does. A NULL return
becomes a `NanuqError` that carries the Rust message.

```nim
type
  DataFrameObj = object
    raw: ptr NqDataFrame
  DataFrame* = ref DataFrameObj

proc `=destroy`(x: DataFrameObj) =
  if x.raw != nil: nq_df_free(x.raw)

proc readCsv*(path: string): DataFrame =
  wrap nq_df_read_csv(path.cstring)   # wrap raises NanuqError on NULL
```

That's all of the machinery. The rest of this page uses it.

## Building a DataFrame from Nim data

Each `series` copies a Nim array into a Polars column, and `$` uses Polars' own
table formatting.
"""

nbCode:
  let people = newDataFrame(
    series("name", ["Ada", "Grace", "Linus", "Margaret"]),
    series("born", [1815, 1906, 1969, 1936]),
    series("height", [1.65, 1.52, 1.80, 1.70]),
  )
  echo people
  echo "shape: ", people.shape
  echo "columns: ", people.columns
  echo "dtype of born: ", people.dtype("born")

nbText: """
## Expressions

`col` and `lit` build Polars expressions, and the usual Nim operators combine them.
Nim literals are lifted automatically, so `col("born") > 1900` works. Nothing is
computed yet. An `Expr` is only a description, and `$` shows how Polars sees it.
"""

nbCode:
  let isModern = col("born") > 1900 and col("height") >= 1.6
  echo isModern
  echo (2026 - col("born")).alias("age")

nbText: """
Eager shortcuts on `DataFrame` run one step right away:
"""

nbCode:
  echo people.filter(isModern)
  echo people.withColumns((2026 - col("born")).alias("years_since_birth"))

nbText: """
## Reading a CSV and running a lazy query

`lazy` turns a DataFrame into a `LazyFrame`, a query plan. Each step returns a new
plan, and nothing runs until `collect`. This lets Polars optimize the whole query
first. Below, the example uses a 12-row sample of the classic iris dataset.
"""

nbCode:
  let iris = readCsv(currentSourcePath.parentDir.parentDir / "examples" / "iris_sample.csv")
  echo iris.head(3)

  let query = iris.lazy
    .filter(col("sepal_length") > 5.0)
    .groupBy(col("species"))
    .agg(
      col("sepal_length").mean.alias("mean_sepal_length"),
      col("petal_width").max.alias("max_petal_width"),
      col("species").count.alias("n"),
    )
    .sort("mean_sepal_length", descending = true)

nbText: """
`explain` prints the optimized plan. Notice the `PROJECT 3/5 COLUMNS` line at the
bottom: Polars noticed that only three columns are used and reads only those.
"""

nbCode:
  echo query.explain

nbCode:
  let summary = query.collect
  echo summary

nbText: """
## Getting values back into Nim

Cells and whole columns can be copied back into ordinary Nim values.
"""

nbCode:
  let top = summary["species", 0, string]
  let topMean = summary["mean_sepal_length", 0, float]
  echo "top species: ", top, " (mean sepal length ", topMean, " cm)"
  echo "counts: ", summary.toSeq("n", int)

nbText: """
## Errors

Polars errors (and panics) are caught on the Rust side and re-raised in Nim with
the original message.
"""

nbCode:
  try:
    discard iris.select(col("petal_colour"))
  except NanuqError as e:
    echo "NanuqError: ", e.msg.splitLines[0]

nbText: """
## What's next

This is a proof of concept. Natural next steps are:

- generate `ffi.nim` with nbindgen instead of by hand,
- move columns without copying through the Arrow C Data Interface,
- add more IO (Parquet, `scan_csv`), joins, and nulls and dates,
- ship prebuilt libraries so users don't need cargo.

Source: [pietroppeter/nanuq](https://github.com/pietroppeter/nanuq).
"""

nbSave
