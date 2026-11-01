# Proposal

## Why

Porting the Nanuq Book chapters to 0.5 (about twelve chapters, against this PR) showed
that nested display matches Python, and that `list.eval`, `struct.field`, `explode`,
`concatList`, `valueCounts` and `str.split` work as written. It also found gaps that the
port had to work around: Series had no `struct`/`list` namespaces and no HTML for
notebooks, `entropy` and `pl.len()` were missing, sized integers (`int32`) did not
build columns, and a few frame calls (`interpolate`, `cast` by data type,
`explode("a", "b")`, `pl.struct("a", "b")`) had no Nanuq spelling.

It is the ninth change of the 0.5 release (#53).

## What Changes

- Series namespaces `s.list`, `s.arr`, `s.struct`, `s.str`, `s.dt`, `s.cat`, with every
  function of the Expr namespace of the same name.
- `toHtml(Series)`, the HTML Python shows for a Series (shape `(n,)`), so nimib's
  `nbShow`-style helpers work on a Series.
- `Expr.entropy(base = E, normalize = true)`.
- `len()`, the row count expression (Python's `pl.len()`).
- Columns from `int8` ... `uint64` and `float32` values (top level, in lists and arrays,
  in `newDataFrame`), and `toList` for those types.
- `asStruct("a", "b")` with column names.
- `interpolate()` on DataFrame and LazyFrame.
- `cast({Float64: Float32})` and `cast({col(SomeNumber): Float32})` on frames.
- `explode("a", "b")` with several column names.

## Capabilities

### Modified Capabilities
- `series`: namespaces, HTML, sized numbers.
- `expressions`: entropy, row count.
- `struct-functions`: structs from column names.
- `frame-verbs`: frame interpolation, casting by data type.
- `list-functions`: exploding several columns by name.

## Differences from Polars

- Python's Series namespaces are separate classes; in Nanuq `s.list.len` runs
  `col(s.name).list.len` on a one-column frame (a macro forwards the call), so every
  Expr namespace function works on a Series, but each call is one small query.
- `len()` needs the parentheses: plain `len` is Nim's length proc.
- `cast` keys are either all data types or all selectors in one call (a Nim table
  literal has one key type); Python mixes names, types and selectors in one dict.
- Selectors are Nanuq's `col(SomeNumber)` (Python `cs.numeric()`).
- `uint64` values above `high(int64)` cannot build a column (they go through `int`).

## Impact

- Rust: `nq_expr_entropy`, `nq_expr_len`.
- `src/nanuq.nim`: Series namespace types and dot-operator macros, `toHtml(Series)`,
  `entropy`, `len()`, sized-number `series` and `toList`, `asStruct(varargs[string])`,
  frame `interpolate`, `cast` by type or selector, `explode(a, b, ...)`.
- Tests in `tests/test_nested.nim`.
