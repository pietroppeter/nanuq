# Design

## Decisions

### One ABI function for the namespace
Polars' string functions differ only in which arguments they take: up to two
expressions (pattern and value, offset and length), up to two booleans (`literal`,
`strict`), a count, a fill character, and for `join` a delimiter string. A single
`nq_expr_str(e, op, a, b, flag1, flag2, n, ch, s)` with an `NqStrOp` enum covers them
all, the same way `nq_expr_unary` covers one-argument functions. A NULL expression
argument means a null literal (for `stripChars()` and an open-ended `slice`).

### `StrNameSpace` is a `distinct Expr`
`col.race.str.replaceAll(...)` reads like Polars, and names can't clash with `Expr`
procs or with future namespaces (`str.len` vs `list.len`). Converting back is free.

### `format` in Nim
Python's `pl.format` splits the template on `{}` and calls `concat_str`; Nanuq does the
same, so no ABI function is needed.
