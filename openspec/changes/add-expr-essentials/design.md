# Design

## Context

Expressions cross the ABI as opaque `Expr` pointers. Binary operators go through
`nq_expr_binary(a, NqBinOp, b)` and one-argument functions through
`nq_expr_unary(e, NqUnary)`. Literals are lifted by `lit`. Polars 0.55 has:
- `when(c).then(a)` returning `Then`, `.when(c)` returning `ChainedWhen`, `.then`
  returning `ChainedThen`, and `.otherwise(e)` returning `Expr`. `Then` and
  `ChainedThen` also convert into `Expr` (otherwise null).
- `is_in(other, nulls_equal)` (feature `is_in`) and `is_between(lower, upper,
  ClosedInterval)` (feature `is_between`).
- `floor_div`, `%` (Rem), `pow` and `abs` (feature `abs`).
- `median`, `var(ddof)`, `std(ddof)`, `quantile(Expr, QuantileMethod)` and `len`.
- `fill_null_with_strategy(FillNullStrategy)` and `over(partition_by)`.

## Goals / Non-Goals

**Goals:**
- One plan, two spellings for conditionals: the chain is the reference, and `choose` is
  sugar that expands to it.
- Strategy and option enums follow the `api-conventions` spec.
- Few new ABI functions: extend `NqBinOp` and `NqUnary` where the shape fits.

**Non-Goals:**
- String, temporal and list namespaces.
- `over` with `order_by` or mapping strategies.

## Decisions

### Conditionals are built in Nim and crossed once
`` `when` `` returns a Nim `When` value holding the condition. `.then(v)` returns a `Then`
value holding lists of conditions and values, and `.when` / `.then` on it extend those
lists. `otherwise(e)`, or the converter to `Expr`, makes one call:

```rust
nq_expr_when_then(conds: *const *const Expr, values: *const *const Expr, n: usize,
                  otherwise: *const Expr /* NULL: none */) -> *mut Expr
```
Rust folds the lists into `when(c0).then(v0).when(c1).then(v1)...` and ends with
`.otherwise(e)`, or `.otherwise(lit(NULL))` when there is none.
- *Why:* a single ABI function and no Rust `Then`/`ChainedThen` handles to free. Nim
  values are cheap.
- *Alternative:* mirror Rust's four builder types across the ABI. That gives four more
  opaque types for no gain.

### `choose` macro
`choose(body)` takes an `if` statement or expression (`nnkIfStmt`/`nnkIfExpr`), and turns
each `elif` branch into `.when(cond).then(value)` and `else` into `.otherwise(value)`.
Any other node is a compile error with a message that points to `if`. Values go through
`lit` when they are not `Expr`. About 30 lines in `src/nanuq.nim`.

### Typed value lifting
`then`, `otherwise` and the macro accept `Expr` or `SomeNumber | string | bool`, as the
binary operators already do. Strings become `lit("...")`.

### `isIn` with Nim values
`isIn(values: openArray[T])` builds a `Series` from the values (the existing `series`
procs), turns it into a literal with `nq_expr_lit_series`, and calls
`nq_expr_is_in(e, other, nulls_equal)`. Rust implodes the literal series when the other
side is a plain column, which is what Polars expects in 0.55.

### Enums
`ClosedInterval`, `QuantileMethod` and `FillNullStrategy` are pure enums with Rust's
names, in Rust's order, mirrored as `NqClosedInterval`, `NqQuantileMethod` and
`NqFillNullStrategy`. Fill uses
`nq_expr_fill_null_strategy(e, strategy, has_limit, limit)`. `forwardFill(limit)` and
`backwardFill(limit)` are Nim one-liners on top. `limit` is `Option[int]`, with
plain-`int` overloads (like `sample`'s `seed`).

### Operators
`NqBinOp` gains `Mod` (Rust `%`), `FloorDiv` and `Pow`. In Nim, `mod`, `div`, `^` and
`pow` are defined with `defBinOp`, so literals on either side work (`2 ^ col("a")`).
`NqUnary` gains `Abs`, `Median`, `Len` and `Neg`.

### `over`
`nq_expr_over(e, partition_by, n)` with key expressions. Nim overloads take a single
name, a list of names, or a list of expressions.

## Risks / Trade-offs

- Macro error messages are harder to read than proc errors. The macro checks the node
  kinds itself and reports "choose expects an if/elif/else expression".
- `mod`/`div` with Polars' floor semantics may surprise Nim users who expect truncation.
  The difference is in the doc comments and the README conventions.
