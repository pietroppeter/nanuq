# Proposal

## Why

Two small gaps found while porting real queries to Nanuq during 0.3:

- The performance work on PDS-H found that query 21 needs an extra group-by and join in
  Nanuq because there is no `Expr.filter`, which aggregates over part of a group
  ("late deliveries per supplier"). That costs about 30% on that query.
- The Nanuq Book port found that Python's `pl.col(["a", "b"])` (or `df.select(cols)` with
  a list in a variable) has no direct twin: `col("a", "b")` takes varargs only.

It is the eighth change of the 0.3 release.

## What Changes

- **`e.filter(predicate)`** keeps the values of `e` where `predicate` is true, for
  conditional aggregations (`agg(col.pts.filter(col.kind == "TT").sum)`).
- **`col(names)`** with an `openArray[string]` returns a `Selector` for those columns, in
  order.

## Capabilities

### Modified Capabilities
- `expressions`: `Expr.filter`.
- `column-selectors`: `col` with a list of names.

## Differences from Polars

- None in behaviour. Python's `Expr.filter` also takes several predicates and keyword
  constraints (`filter(a, b, kind="TT")`); Nanuq takes one expression (combine with
  `and`).

## Impact

- `src/rust/src/lib.rs`: `nq_expr_filter`; `src/nanuq/ffi.nim`, `src/nanuq.nim`.
- Tests in `tests/test_expressions.nim` and `tests/test_selectors.nim`.
