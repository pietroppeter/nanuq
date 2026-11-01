# Proposal

## Why

After 0.5 the book map (planning/book-ports-0.6.md) still finds sections blocked by
single functions: `append` 5, `unstack` 3, ranges 3, method spellings (`mul`, `sub`) 4,
`dtype_of` 4, `join_where`, `rolling_map`, `explain_all`, `is_sorted`, `from_epoch`,
`read_parquet_schema`, `hist`, `scatter`/`set`, `remove`. Each is small; together they
unblock about 25 sections.

It is the ninth change of the 0.6 release.

## What Changes

- Method spellings of operators: `add`, `sub`, `mul`, `truediv`, `floordiv`, `eq`, `ne`,
  `lt`, `le`, `gt`, `ge`, `neg`; `xor` (logical on booleans, bitwise on integers).
- `intRanges`, `dateRanges`, `datetimeRanges` (one list per row), `arange` (`intRange`).
- `joinWhere(other, predicates...)` (inequality joins), `explainAll(lfs)`.
- `hist` on Expr and Series; `setSorted` on Expr and DataFrame; `Series.isSorted`.
- `append` (frame, in place), `remove(predicate)` (the opposite of `filter`).
- `fromEpoch(column, EpochUnit)`, `readParquetSchema(path)`, `threadPoolSize()`.
- `unstack(step, how, columns, fillValues)`.
- `rollingMap(f, windowSize, minPeriods, center)` with a typed Nim proc of a window.
- `Series.scatter(indices, values)` and `Series.set(mask, value)`.
- `dtypeOf(expr | column)` with `cast(e, dtypeOf(...))`, `display` and `innerDtype`.

## Capabilities

### New Capabilities
- `frame-utilities-0-6`: the functions above.

## Differences from Polars

- Python's `and_`/`or_` methods have no Nim spelling (a trailing underscore is not a Nim
  identifier); `a.and(b)` and `a.or(b)` already work as operator calls (`` a.`and`(b) ``).
- `rollingMap` passes the window's non-null values as a `seq[T]` to a typed proc
  (Python passes a Series to a Python function) and runs on the whole column at once,
  without `weights`.
- `unstack` takes a `fillValues` expression (Python also takes a list per column).
- `fromEpoch` takes an `EpochUnit` enum (Python strings `"d"`, `"s"`, `"ms"`, `"us"`,
  `"ns"`).
- `dtypeOf` supports `cast`, `display` and `innerDtype`; the rest of Python's datatype
  expressions (`matches`, `to_dtype`, struct and integer helpers) is left out.
- `set` is spelled `` `set` `` when called with a prefix (`` s.`set`(mask, 0) ``), as
  `set` is also Nim's set type.
- `hist` on a Series includes `breakpoint` and `category` by default, as Python does;
  on an Expr it does not.

## Impact

- `src/rust/src/lib.rs`, `src/nanuq/ffi.nim`: `nq_expr_xor`, `nq_expr_set_sorted`,
  `nq_expr_hist`, `nq_expr_int_ranges`, `nq_expr_date_ranges`, `nq_lf_join_where`,
  `nq_explain_all`, `nq_thread_pool_size`, `nq_expr_cast_dtype_of`,
  `nq_expr_dtype_display`.
- `src/nanuq.nim`: the procs above (several in Nim on top of existing API).
- New `tests/test_utilities6.nim`.
