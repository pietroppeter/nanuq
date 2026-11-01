# Design

## Context

`col` is a proc today, plus a macro (`col(SomeNumber)`) and a proc with two or more
names returning a `Selector`. Python Polars' `pl.col` is an object with a `__call__` and
a `__getattr__`, so `pl.col("a")` and `pl.col.a` both work. `newDataFrame` is a proc
over `varargs[Series]`. Polars 0.55 has `Expr::true_div`, `Expr::null_count` and
`Expr::rank(RankOptions { method, descending }, seed)` (feature `rank`).

## Decisions

### `col` is a constant with call and dot operators
`const col* = ColNs()` with `` `()` `` overloads for every existing form (one name,
several names, the type selector macro), and a `` `.` `` template that turns
`col.race` into `col("race")`. The experimental `callOperator` and `dotOperators`
features only need to be enabled where the operators are declared, so user code needs
no pragma (checked with Nim 2.2.4). The dot template only fires when nothing else
matches, so `col.len` is a column but `col.repr` is `system.repr`.

Alternative considered: a `col` macro taking an `untyped` dot expression. It can't tell
`col.a` from `col(a)` where `a` is a variable, and macros can't be overloaded on
untyped arguments cleanly.

### `newDataFrame` is a macro over `varargs[untyped]`
A macro with one `untyped` parameter and a proc over `varargs[Series]` don't overload:
the block form gets sem-checked against the proc and fails. So `newDataFrame` becomes a
single macro. With one block argument it rewrites each `name: [values]` line to
`series("name", values)`; with anything else it forwards the arguments unchanged to the
old proc (now private), so `newDataFrame(series(...), series(...))`,
`newDataFrame(someSeq)` and `newDataFrame()` keep working.

`nil` inside a bracket turns the bracket into `[some(a), none(typeof(a)), ...]`, with the
type taken from the first non-nil value. A bracket of only `nil` fails to compile: there
is no type to infer.

### True division through `NqBinOp`
`NqBinOp.Div` now maps to `Expr::true_div`. Rust's truncating `/` is not exposed (`div`
already gives floor division, which is what integer code wants). No new ABI function.

### `rank`
`nq_expr_rank(e, NqRankMethod, descending, has_seed, seed)`. Polars returns f64 for
`Average` and `u32` otherwise; Nanuq passes that through.

## Risks / Trade-offs

- `col` as a constant: code that took `col` as a proc value (`names.map(col)`) breaks;
  `names.mapIt(col(it))` works. Nothing in the repo does that.
- Changing `/` silently changes results of 0.2 code. Nanuq has no users yet, and the
  CHANGELOG says so under "Changed".
