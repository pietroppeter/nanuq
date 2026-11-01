# Proposal

## Why

Porting the Nanuq Book chapters to 0.4 (nanuq-book#6) worked, and every Nim frame
matched Python, but the port worked around a few gaps that are small to close:
`any`/`all` aggregations (the book used min/max on booleans), a null literal
(`fill_nan(None)`), `groupBy` with column names, and frame `gatherEvery`. It also found
that eager `df.groupBy(...).agg(...)` returned a LazyFrame, unlike Python.

It is the thirteenth change of the 0.4 release (#51). The larger items from the same
list go to BACKLOG.md.

## What Changes

- `Expr.any(ignoreNulls)` and `Expr.all(ignoreNulls)` aggregations (also on Series).
- `lit(nil)` null literal and `fillNan(nil)`.
- `groupBy("a", "b")` and `select("a", "b")` with column names, on DataFrame and LazyFrame (select from the explainer port).
- `gatherEvery(n, offset)` on DataFrame and LazyFrame.
- **BREAKING** On a DataFrame, `groupBy`, `groupByDynamic` and `rolling` return a
  `GroupBy` whose `agg` returns a DataFrame, as in Python (it returned a LazyFrame, so
  eager code needed `.collect`). LazyFrame keeps `LazyGroupBy`.

## Capabilities

### Modified Capabilities
- `expressions`: boolean aggregations.
- `missing-values`: null literal.
- `dataframe-api`: `groupBy` by name; eager `agg` returns a DataFrame.
- `frame-verbs`: every n-th row.

## Differences from Polars

- Python writes `pl.lit(None)` and `fill_nan(None)`; Nanuq writes `lit(nil)` and
  `fillNan(nil)`.
- `any` and `all` on a Series return a one-value Series (`s.all.item(bool)`), as other
  Series aggregations do; Python returns a bool.
- `all()` with no argument stays the column selector, as Python's `pl.all()`.

## Impact

- Rust: `nq_expr_lit_null`, `nq_expr_any_all`.
- `src/nanuq.nim`: `lit(nil)`, `fillNan(nil)`, `any`, `all`, `groupBy(varargs[string])`,
  frame `gatherEvery`, the `GroupBy` type.
- Tests in `tests/test_expressions.nim`, `tests/test_nulls.nim`, `tests/test_verbs.nim`.
