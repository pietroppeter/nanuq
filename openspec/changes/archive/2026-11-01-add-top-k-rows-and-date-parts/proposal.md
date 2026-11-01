# Proposal

## Why

The 0.4 explainer ("Counting El Niños") was drafted in Python Polars first. Its
findings list the calls the 0.4 API could not mirror. The most used call in the post,
`df.top_k(5, by="peak")`, returns whole rows, and 0.4 had only the one-column
`Expr.topK`. The post also builds dates from year and month columns
(`pl.date(year, month, 15)`) and prints its tables with `pl.Config(float_precision=2)`.

It is the twelfth change of the 0.4 release (#51).

## What Changes

- Frame `topK(k, by, reverse)` and `bottomK(k, by, reverse)`, eager and lazy.
- `date(year, month, day)` with expression parts gives a Date column.
- `setFloatPrecision(n)`, and `floatPrecision` in `setConfig` and `withConfig`.
- Specs now state two things that already worked: `groupBy` keeps first-seen group
  order, and `joinAsof(coalesce = false)` keeps the right key.

## Capabilities

### New Capabilities
(none)

### Modified Capabilities
- `value-functions`: top k rows.
- `temporal`: dates from parts.
- `inspection`: float precision.
- `temporal-grouping`: `coalesce` in the as-of join requirement.
- `dataframe-api`: group order.

## Differences from Polars

- Python's `top_k` does not promise an order; Nanuq returns largest first (`bottomK`:
  smallest first), which is what Rust Polars does.
- `reverse` is one bool for all keys; Python also takes a list.
- `date` with three numbers returns a Nim `Date` value, not an expression (use
  `lit(date(2026, 1, 1))` for a literal column).
- Nanuq's `groupBy` always keeps group order; Python's default (`maintain_order=False`)
  does not, and Nanuq has no `maintainOrder` parameter.
- `datetime(year, month, day, hour, ...)` is not added: `datetime` would clash with
  std/times' `dateTime` (Nim names are style-insensitive). It can come with a better name
  later.

## Impact

- Rust: `nq_lf_top_k`, `nq_expr_date`, `nq_set_float_precision`,
  `nq_get_float_precision`.
- `src/nanuq.nim`: `topK`/`bottomK` frame overloads, `date` expression, float precision
  in the display config.
- Tests in `tests/test_values.nim`, `tests/test_temporal.nim`, `tests/test_inspection.nim`.
