# Proposal

## Why

Struct columns (add-nested-dtypes) need their functions: `struct.field` blocks 11 book
sections, `pl.struct(...)` 9, `unnest` 8 and `value_counts` 12 (Polars' expression
`value_counts` returns a struct). The `arr` namespace for Array columns comes along, as
the coverage map pairs them.

It is the fourth change of the 0.5 release.

## What Changes

- `asStruct(exprs)` builds a struct column (Python's `pl.struct`).
- `e.struct`: `field(name)` (also `e.struct["name"]`), `field(names)` and `field(index)`,
  `unnest` (all fields as columns), `renameFields`, `withFields`, `jsonEncode`.
- `df.unnest(columns, separator)` (eager and lazy): fields become columns.
- `Expr.valueCounts(sort, parallel, name, normalize)` gives a struct of value and count.
- `e.arr`: `len`, `sum`, `min`, `max`, `mean`, `median`, `std`, `var`, `argMin`, `argMax`,
  `first`, `last`, `get`, `join`, `contains`, `countMatches`, `sort`, `slice`, `head`,
  `tail`, `shift`, `toList`, `toStruct`, `explode`, `eval`, `agg`.

## Capabilities

### New Capabilities
- `struct-functions`: struct construction, the struct and arr namespaces, unnest and
  expression valueCounts.

## Differences from Polars

- The constructor is `asStruct` (the Rust name): `struct` is the namespace,
  `col("a").struct`, and `struct(col("a"))` could not be told apart from it.
- `asStruct` takes expressions only; Python also takes keyword arguments
  (`pl.struct(x=...)`): use `.alias`.
- `struct.withFields` refers to the struct's own fields with `col` inside
  `struct.field`, not with Python's `pl.field`.
- `arr.toStruct` names the fields `field_0`, ...; Python can also take a function.
- No `prefixFields`/`suffixFields` (not in Rust Polars 0.55's DSL).

## Impact

- `src/rust/src/lib.rs` and `src/nanuq/ffi.nim`: `nq_expr_struct`, `nq_as_struct`,
  `nq_expr_value_counts`, `nq_lf_unnest`, `nq_expr_arr`.
- `src/nanuq.nim`: `StructNameSpace`, `ArrayNameSpace`.
- New `tests/test_structs.nim`.
