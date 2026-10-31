# Proposal

## Why

The 0.3 explainer ("Aged 19") and the Nanuq Book ports keep tripping over small things in
the 0.2 API: `toSeq` clashes with `sequtils.toSeq`, `col("a") / col("b")` silently
truncates integers, every tiny frame repeats `series(...)` for each column, `col("race")`
is noisy next to Python's `pl.col.race`, there is no way to count nulls inside a query,
and shared places in a ranking need `rank`. None of them is big, and all of them change
how the rest of 0.3 reads, so they land first.

This change takes up the BACKLOG.md entries "Block syntax for building a dataframe",
"`/` on two integer columns: open design question" and "`toSeq` clashes with
`sequtils.toSeq`". It is the first change of the 0.3 release. The API choices were made
by Pietro on 2026-10-31 in the 0.3 design discussion (dev log "Designing Nanuq 0.3",
section 7, and the decisions that followed it): true division for `/` because Nim's `/`
is closer to Python than to Rust, `col.name` shorthand, string keys and `nil` in the
block syntax, `Expr.nullCount`, and `rank` with ties.

## What Changes

- **BREAKING: `toSeq` is renamed `toList`** (Polars' `to_list`), for plain and `Option`
  types. `toSeq(walkFiles("*.csv"))` compiles again with Nanuq imported.
- **BREAKING: `/` is true division.** `col("a") / col("b")` on integers gives f64, as
  in Python Polars and Nim (`7 / 2 == 3.5`); a division by zero gives `inf` or `NaN`.
  `div` stays Polars' floor division.
- **`col.name` shorthand**: `col.race` is `col("race")`, as Python's `pl.col.race`.
  `col` becomes a constant whose call operator keeps every existing form working:
  `col("a")`, `col("a", "b")`, `col(SomeNumber)`, `col(float, int)`.
- **Block syntax for `newDataFrame`**:
  ```nim
  let df = newDataFrame:
    rider: ["Pogačar", "Seixas"]
    wins: [22, nil]          # nil is a missing value
    "nrs + 5": [1, 2]        # string keys for names that aren't identifiers
  ```
  Each line becomes `series(name, values)`. A bracket holding `nil` becomes an `Option`
  column typed from its other values. `newDataFrame()` with no columns stays valid.
- **`Expr.nullCount`**: the number of nulls as an aggregation, `col.a.nullCount`.
- **`rank(rankMethod = Average, descending = false, seed = none(int))`** with a pure enum
  `RankMethod` (`Average`, `Min`, `Max`, `Dense`, `Ordinal`, `Random`). Written
  positionally, `rank(Min, descending = true)`, because `method` is a Nim keyword.
- Polars feature `rank` is compiled in. The crate version becomes `0.3.0-dev`.

## Capabilities

### New Capabilities

None.

### Modified Capabilities
- `dataframe-api`: `toList`, the block syntax, the `col.name` shorthand and true
  division.
- `missing-values`: `toList` in the null reads, and `Expr.nullCount`.
- `data-types`: `toList` in the casting scenario.
- `frame-verbs`: `toList` in the row window example.
- `expressions`: `rank` and `RankMethod`.
- `native-bridge`: `NqRankMethod` joins the enums kept in the same order.

## Differences from Polars

Expected differences from Polars' Rust and Python APIs:

- **`/`** matches Python Polars (`truediv`), not Rust Polars' `/` operator, which
  truncates integer division and gives null for a division by zero. This is the one
  operator where Nanuq picks Python over Rust, because Nim's own `/` does the same.
- **`col.name`** works for any column name that is a Nim identifier, keywords such as
  `end` included. A few names are taken by Nim before the shorthand sees them: `type`,
  and procs from `system` that accept anything, such as `repr` and `sizeof`. Those
  columns need `col("type")`. Python's `pl.col.name` has similar gaps (methods of
  `pl.col`), different ones.
- **Block syntax** has no Polars counterpart: Python writes a dict
  (`pl.DataFrame({"a": [...]})`), Rust the `df!` macro (`df!("a" => [...])`). Missing
  values are `nil` where Python writes `None`.
- **`rank`**'s method is a positional argument: Python's keyword `method=` can't be a
  Nim named argument because `method` is a keyword. The parameter is named `rankMethod`.
  The default is `Average`, as in Python (Rust has no default). `seed` applies only to
  `Random`.
- **`toList`** takes the Nim element type: `df.toList("a", int)`. Python's
  `Series.to_list()` infers it.
- **Names** follow Polars in camelCase: `null_count` → `nullCount`, `to_list` → `toList`.

## Impact

- `src/rust/src/lib.rs`: `NqBinOp` gains `TrueDiv` and `/` maps to it; new
  `nq_expr_rank` with `NqRankMethod`; `NqUnary` gains `NullCount`. `Cargo.toml` adds the
  `rank` feature and moves to `0.3.0-dev`.
- `src/nanuq/ffi.nim` and `src/nanuq.nim`: the declarations, `toList`, `ColNs` with call
  and dot operators, the `newDataFrame` macro, `nullCount`, `rank`.
- `src/nanuq/datamancer.nim`, tests, README, dev log posts and examples move from `toSeq`
  to `toList`.
- `tests/test_basic.nim` and `tests/test_expressions.nim` cover the new API.
