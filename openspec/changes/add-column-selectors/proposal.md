# Proposal

## Why

Real tables have many columns, and many queries treat a group of them the same way: the
mean of every numeric column, every column except the ID, all the `weight_*` columns.
Nanuq can only name columns one at a time today. Polars solves this with selectors, and
the 0.2 explainer post needs them (the census scene "mean of every numeric column per
station, except the cub count").

This is the fifth change of the 0.2 release (see the Polars coverage map, area "Column
selection"). It has no BACKLOG.md entry. Pietro made the API choice on 2026-10-31 in the
doc "Nanuq 0.2: API choices the explainer forces": select by Nim type through `col`, with
`all()`, `exclude`, and regex. No set operators in 0.2. Add `name.suffix`/`name.prefix`,
because applying two aggregations to one selector otherwise gives duplicate names.

## What Changes

- **By Nim type**: `col(SomeNumber)` selects every numeric column. Each Nim typeclass maps
  onto a Polars dtype category:
  - `SomeInteger` is Integer
  - `SomeSignedInt` and `SomeUnsignedInt` are the signed and unsigned integers
  - `SomeFloat` is Float
  
  A concrete type selects exactly that dtype (`col(int)` is i64, `col(string)` is str),
  and several types select their union: `col(float, int)`. A type with no dtype, such as
  `col(seq[int])`, does not compile.
- **By name**: `col("a", "b")` selects several columns, `all()` selects every column, and
  `col("^weight_.*$")` selects by regex, as in Polars.
- **`exclude`**: `col(SomeNumber).exclude("cubs")` and `all().exclude("id", "name")`.
- **Selectors are expressions**: a `Selector` converts to `Expr`, so
  `col(SomeNumber).mean`, `select(all().exclude("id"))` and `agg(col(SomeFloat).max)` all
  work, and Polars expands the expression to one column per selected column.
- **Output names**: `e.name.suffix("_mean")` and `e.name.prefix("avg_")`. They rename every
  column an expression produces, for example
  `agg(col(SomeNumber).mean.name.suffix("_mean"), col(SomeNumber).max.name.suffix("_max"))`.
- The ABI stays `0.2.0-dev`, and no Polars features are added.

## Capabilities

### New Capabilities
- `column-selectors`: selecting columns by Nim type, by several names, by regex or all
  of them, with `exclude`, and renaming the outputs with `name.suffix`/`name.prefix`.

### Modified Capabilities
- `native-bridge`: the dtype category enum joins the ones that keep the same order in
  Rust and `ffi.nim`.

## Differences from Polars

Expected differences from Polars' Rust and Python APIs:

- **Nim types instead of a selectors module.** Python's `cs.numeric()`, `cs.integer()`,
  `cs.float()`, `cs.string()` and `cs.by_dtype(pl.Int64)` become `col(SomeNumber)`,
  `col(SomeInteger)`, `col(SomeFloat)`, `col(string)` and `col(int)`. This is the same idea
  as `cast(int32)`. There is no `cs` namespace.
- **No set operators.** Python's `cs.numeric() - cs.by_name("year")` and `|`, `&`, `^`, `~`
  are left out, because on expressions `-` already means subtraction. `exclude` covers
  the common case.
- **`exclude` takes names only.** Excluding by dtype (`exclude(pl.Int64)`) is left for
  later.
- **`col` with one name stays an `Expr`.** Several names, types, or `all()` give a
  `Selector`. A `Selector` converts to `Expr` automatically, so it works wherever an
  expression does.
- **Not in this change:** `cs.starts_with`, `ends_with`, `contains`, `by_index`, `first`/`last`,
  `temporal`, `categorical`, `name.map`, `name.keep` and `name.to_uppercase`. Regex covers
  the name patterns.
- **Names** follow Polars in camelCase: `name.suffix` and `name.prefix` are spelled as in
  Polars.

## Impact

- `src/rust/src/lib.rs`:
  - `nq_expr_selector` builds a Polars `Selector` from names, dtype codes, a dtype category,
    a wildcard flag and excluded names, and returns it as an `Expr`.
  - `nq_expr_name_affix` adds a suffix or prefix.
  - New `#[repr(C)]` enum `NqDtypeClass`.
- `src/nanuq/ffi.nim` and `src/nanuq.nim`: the `Selector` value type with its converter to
  `Expr`, `col` overloads for types, typeclasses and several names, `all`, `exclude`,
  `name.suffix` and `name.prefix`.
- `tests/test_selectors.nim`: each selector form, `exclude`, regex, use in `select`,
  `withColumns` and `agg`, and suffixes that avoid duplicate names.
- `README.md` lists the selectors.
