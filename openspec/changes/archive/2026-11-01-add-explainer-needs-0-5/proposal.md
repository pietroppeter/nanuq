# Proposal

## Why

Porting the 0.5 explainer "Above 4000" from Python to Nim (all 30 cells match
py-polars) needed three workarounds: there is no frame-level `fillNull(value)`
(`df.fill_null(0)`), frame `filter` takes one predicate where Python takes several, and
`groupBy` has no `maintainOrder` parameter.

It is the twelfth change of the 0.5 release (#53).

## What Changes

- `fillNull(value)` and `fillNull(strategy)` on DataFrame and LazyFrame. A number fills
  the numeric columns (a float makes integer columns Float64), a string the String
  columns, a bool the Boolean ones, as Python's `matches_supertype=True` default does.
- `filter(a, b, ...)` on frames with several predicates, joined with `and`.
- `groupBy(..., maintainOrder = ...)` accepted for parity; Nanuq always keeps the
  first-seen group order.

## Capabilities

### Modified Capabilities
- `missing-values`: frame-level null filling.
- `frame-verbs`: several filter predicates; `maintainOrder` on `groupBy`.

## Differences from Polars

- `maintainOrder = false` still keeps the order (Nanuq groups are always ordered).
- No `matchesSupertype = false` option.

## Impact

- `src/nanuq.nim` only. Tests in `tests/test_nulls.nim` and `tests/test_verbs.nim`.
