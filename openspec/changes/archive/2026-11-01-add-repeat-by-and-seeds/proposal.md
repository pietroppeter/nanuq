# Proposal

## Why

The 0.5 book port of the O'Reilly chapter 8 examples found two more small gaps:
`Expr.repeatBy` was missing, and `sample(n, seed = 42)` needed `seed = some(42)` on
expressions and lists (frames and `shuffle` already took a plain int).

It is the eleventh change of the 0.5 release (#53).

## What Changes

- `Expr.repeatBy(by)`, with `by` a count, a column name or an expression: each value
  repeated as a list.
- `sample(..., seed = 42)` with a plain int on Expr and on `list`.

## Capabilities

### Modified Capabilities
- `list-functions`: repeating values into lists; seeds as plain ints.

## Differences from Polars

- None in behaviour. Python's `seed=None` is Nanuq's default; a seed is given as an int.

## Impact

- Rust: `nq_expr_repeat_by`.
- `src/nanuq.nim`: `repeatBy`, `sample` overloads with `seed: int`.
