# Proposal

## Why

Nanuq has no Nim-side notion of a data type. `dtype(df, col)` returns Polars' display
string ("i64", "str"), so code has to compare strings, and nothing can ask Polars to
convert a column. Several parts of the 0.2 plan need a real type value first: `cast`,
dtype column selectors, and CSV schema overrides. This change adds that type value,
schemas, and casting, so the other 0.2 changes can build on it.

This change takes up the casting part of the BACKLOG.md entry "More expressions" (API).
The rest of that entry stays in the backlog. It is the first change of the 0.2 release
(see the Polars coverage map, areas "Data types" and "Casting and types").

## What Changes

- New `DataType` value with a `kind` (`DataTypeKind`) covering Polars' primitive dtypes:
  Boolean, Int8, Int16, Int32, Int64, UInt8, UInt16, UInt32, UInt64, Float32, Float64,
  String and Null. Dtypes Nanuq does not model yet (Date, List, Categorical, ...) come
  back as kind `dkOther` and keep Polars' name.
- Constants named as in Polars: `Boolean`, `Int8` ... `UInt64`, `Float32`, `Float64`,
  `String`, `Null`. `$` gives Polars' short name ("i64"), as today.
- Predicates `isInteger`, `isSignedInteger`, `isUnsignedInteger`, `isFloat`,
  `isNumeric`.
- **BREAKING:** `dtype(df, col)` returns a `DataType` instead of a string. Code that
  compares with strings (`df.dtype("a") == "i64"`) must compare with constants
  (`== Int64`) or use `$`.
- New `schema(df)` and `collectSchema(lf)`: the column names and types, in order, as a
  `Schema` (an `OrderedTable[string, DataType]`). New `dtypes(df)`.
- New `cast`, `strict = true` by default. The target is a Nim type where one is enough:
  `col("a").cast(int32)`, `df.cast(float64)` (all columns). Named columns of a frame take
  `DataType` values, since a list can't hold different typedescs:
  `df.cast({"a": Int32, "b": Float32})`. Every form also accepts a `DataType`.
- New `dataType(T)` maps a Nim type to its `DataType`: `int8` .. `int64`, `uint8` ..
  `uint64`, `float32`, `float64`, `bool`, `string`; `int` and `float` map to `Int64`
  and `Float64`, matching how `series` builds them.
- The C ABI version moves to `0.2.0-dev`. Until `lib-v0.2.0` is released, building from
  a checkout compiles the Rust library from source (prebuilt archives are only fetched
  for released versions).

## Capabilities

### New Capabilities
- `data-types`: the `DataType` value, schemas, and casting.

### Modified Capabilities
- `native-bridge`: the enums that must keep the same order in Rust and `ffi.nim` now
  include `NqDtype`.

## Differences from Polars

Expected differences from Polars' Rust and Python APIs:

- **One value type, not a class hierarchy.** Python has classes (`pl.Int64`,
  `pl.Datetime("ms")`) under `pl.DataType`; Rust has the `DataType` enum with data in
  some variants. Nim gets an object variant with a `kind` enum, which can grow
  parameters (time unit, inner type) later. The constants keep Polars' names, so
  `df.cast({"a": Int32})` reads like Python.
- **Nim types as cast targets.** Polars only takes its own dtypes. Nanuq also takes Nim
  types (`col("a").cast(int32)`), like `toSeq(df, "a", int)` does for reads. `dtype` and
  `schema` still return `DataType` values: a Nim type can't be returned at run time.
- **Unmodelled dtypes.** Polars knows every dtype. Nanuq maps the ones it does not model
  yet to `dkOther` with Polars' name, and refuses to `cast` to them.
- **No 128-bit integers, no Decimal.** `Int128`, `UInt128` and `Decimal` are left out
  (they need extra Polars features); they would read as `dkOther`.
- **`$` is Polars' short name.** Python prints `Int64`; Rust's `Display` prints `i64`.
  Nanuq follows Rust, which is also what the table header shows in both. Nim names
  (`int64`, `string`) were considered and dropped: `$df` is rendered by Polars, so the
  tables would disagree with `$` or need their dtype row rewritten.
- **Schema type.** Python's `pl.Schema` is an ordered mapping; Nanuq uses Nim's
  `OrderedTable[string, DataType]`. Python's `df.schema` is a property; in Nim it is a
  proc, `df.schema` reads the same.
- **`cast` is a Nim keyword.** Method-call syntax works (`col("a").cast(int32)`,
  `df.cast(float64)`), but the prefix form needs backticks: `` `cast`(col("a"), int32) ``.
- **Frame cast arguments.** Python's `df.cast({"a": pl.Int32})` takes a dict; Nim takes
  an `openArray[(string, DataType)]`, written with the same braces:
  `df.cast({"a": Int32})`.
- **Strict default.** Like Python and Rust's `strict_cast`, `cast` fails when a value
  can't be converted; `strict = false` turns those values into nulls, like Polars.
- **No builders for other widths.** `series` still builds int64, float64, bool and
  string columns; other widths come from `cast`. Reading any integer column as `int`
  and any numeric column as `float` works as today.
- **Names** follow Polars in camelCase: `collect_schema` → `collectSchema`,
  `is_integer` → `isInteger`, `is_signed_integer` → `isSignedInteger`,
  `is_unsigned_integer` → `isUnsignedInteger`, `is_float` → `isFloat`,
  `is_numeric` → `isNumeric`.

## Impact

- `src/rust/src/lib.rs`: a `#[repr(C)]` `NqDtype` enum, `nq_df_column_dtype_kind`,
  `nq_lf_collect_schema` (an empty DataFrame carrying the schema), `nq_expr_cast`,
  `nq_lf_cast`. `nq_df_column_dtype` (the string) stays and names `dkOther` dtypes.
  `Cargo.toml` adds Polars features `dtype-i8`, `dtype-i16`, `dtype-u8`, `dtype-u16`
  and moves to version `0.2.0-dev`. The Rust library is rebuilt, so the first CI run
  takes about 10 minutes.
- `src/nanuq/ffi.nim`, `src/nanuq.nim`: the matching declarations and API; imports
  `std/tables`.
- `src/nanuq/datamancer.nim` and the HTML table switch from dtype strings to `DataType`.
- `tests/`: dtype string comparisons become constant comparisons; new tests for
  schemas and casts. The dev-log post "How Nanuq works" still prints `dtype` with
  `echo`, so its output is unchanged.
- `README.md`: the API list mentions `schema` and `cast`.
