# Proposal

## Why

Nanuq's expressions can do arithmetic, comparisons and a handful of aggregations. Most
real queries need a few more things: a conditional column (`when/then/otherwise`), a
membership or range test, modulo and powers, a median or a quantile, filling nulls from
the row above, and aggregates computed per group without collapsing rows (`over`). These
are the expressions the 0.2 explainer post leans on, and the ones users reach for first
after `filter` and `groupBy`.

This change takes up part of the BACKLOG.md entry "More expressions" (`when/then/otherwise`
and window functions; string functions stay in the entry). It is the fourth change of the
0.2 release (see the Polars coverage map, area "Expressions"). The API choices for
conditionals and fill strategies were made by Pietro on 2026-10-31 in the doc "Nanuq 0.2:
API choices the explainer forces" (options A + D for conditionals, with the macro named
`choose`; option A + B for fill strategies).

## What Changes

- **Conditionals**, two spellings for one plan:
  - The Polars chain: `` `when`(cond).then(a).when(cond2).then(b).otherwise(c) ``. Only the
    first `when` needs backticks, because `when` is a Nim keyword. A chain without
    `otherwise` gives null for unmatched rows. A chain converts to `Expr` automatically.
  - A `choose` macro over Nim's `if`/`elif`/`else`, which builds the same chain:
    ```nim
    let size = choose:
      if col("weight_kg") < 150: "cub"
      elif col("weight_kg") < 500: "adult"
      else: "chonk"
    ```
  - Strings in `then`, `otherwise` and the macro branches are literal values, not column
    names. Use `col("x")` for a column.
- **Membership and ranges**: `isIn([1, 2, 3])` (Nim values) or `isIn(expr)`, with
  `nullsEqual = false`. `isBetween(lower, upper, closed = Both)`, where `closed` is a
  `ClosedInterval` (`Both`, `Left`, `Right`, `None`).
- **Arithmetic**: `mod` (Polars' `%`), `div` (Polars' floor division `//`), `pow` and
  `^`, `abs`, and unary `-`.
- **Aggregations**: `median`, `var(ddof = 1)` (written `e.var`), `std(ddof = 1)` (gains
  `ddof`), `quantile(q, method = Nearest)` with a `QuantileMethod` (`Nearest`, `Lower`,
  `Higher`, `Midpoint`, `Linear`, `Equiprobable`), and `len` (rows including nulls, unlike
  `count`).
- **Null strategies**: `fillNull(Forward)`, `fillNull(strategy = Backward, limit = 2)`
  with a `FillNullStrategy` (`Forward`, `Backward`, `Mean`, `Min`, `Max`, `Zero`, `One`),
  and the shortcuts `forwardFill(limit)` and `backwardFill(limit)`. `fillNull(value)` is
  unchanged.
- **Windows**: `over("station")`, `over(["a", "b"])` or `over([expr])` computes an
  expression per group and broadcasts it back to the rows.
- New pure enums `ClosedInterval`, `QuantileMethod` and `FillNullStrategy`, following the
  `api-conventions` spec. Polars features `is_in`, `is_between` and `abs` are compiled
  in. The ABI stays `0.2.0-dev`.

## Capabilities

### New Capabilities
- `expressions`: conditionals, membership and range tests, extra arithmetic and
  aggregations, null fill strategies and window expressions.

### Modified Capabilities
- `native-bridge`: the new enums join the ones that keep the same order in Rust and
  `ffi.nim`.

## Differences from Polars

Expected differences from Polars' Rust and Python APIs:

- **`when` is backticked** as a prefix call: `` `when`(cond) ``. `.then`, `.when` and
  `.otherwise` are written as in Polars. `choose` is Nanuq's own sugar and has no Polars
  counterpart. It builds the same plan, so `$expr` shows Polars' `when/then/otherwise`.
- **Strings are values in conditionals.** Python's `.then("cub")` means the *column*
  "cub", a known gotcha that needs `pl.lit("cub")`. In Nanuq a string is a literal, as in
  `fillNull("x")` today.
- **Operators**: Python's `%`, `//` and `**` become Nim's `mod`, `div` and `^` (or
  `pow`). They keep Polars' semantics, not Nim's: `mod` and `div` round towards negative
  infinity (`-7 mod 3 == 2`), where Nim's integer `mod`/`div` truncate.
- **`var`** is a Nim keyword, so it is written `e.var` (or `` `var`(e) ``).
- **Option values are enums**: `closed = Left`, `method = Linear`, `fillNull(Forward)`.
  Rust's `FillNullStrategy::Forward(limit)` carries the limit, but a pure enum can't carry
  data, so `limit` is a separate argument, as in Python.
- **`quantile`** takes a float, not an expression, in this change.
- **`over`** takes only the partition keys. Python's `order_by` and `mapping_strategy`
  are left for later.
- **Not in this change:** string functions, `cum_*`, `rank`, `diff`, `shift`, `round`,
  `log`/`exp`, rolling windows, `is_duplicated`/`is_unique`, `replace`, and
  `when` with several conditions per branch (`when(a, b)`, write `a and b`). They stay in
  the coverage map.
- **Names** follow Polars in camelCase: `is_in` → `isIn`, `is_between` → `isBetween`,
  `fill_null` → `fillNull`, `forward_fill` → `forwardFill`, `nulls_equal` → `nullsEqual`.

## Impact

- `src/rust/src/lib.rs`:
  - `nq_expr_when_then` builds a whole chain from lists of conditions and values plus an
    optional otherwise.
  - `nq_expr_is_in`, `nq_expr_is_between`, `nq_expr_quantile`, `nq_expr_var_std` (ddof),
    `nq_expr_fill_null_strategy`, `nq_expr_over` and `nq_expr_lit_series` (for `isIn`
    with Nim values).
  - New `NqBinOp` values `Mod`, `FloorDiv` and `Pow`; new `NqUnary` values `Abs`,
    `Median`, `Len` and `Neg`.
  - `Cargo.toml` adds three features.
- `src/nanuq/ffi.nim` and `src/nanuq.nim` get the declarations, the three enums, the
  chain types with their converter to `Expr`, the `choose` macro and the procs.
- `tests/test_expressions.nim` covers every function and option, and checks that the
  macro and the chain give the same plan.
- `README.md` lists the new expressions. `BACKLOG.md` keeps "More expressions" for string
  functions only.
