# Design

## Context

`nq_df_column_dtype` returns `col.dtype().to_string()`. Nim exposes it as
`dtype(df, col): string`, and `datamancer.nim`, the HTML table and the tests compare
those strings. Expressions cross the C ABI as opaque `Expr` pointers, and enums
(`NqBinOp`, `NqUnary`) as `#[repr(C)]` integers mirrored in `ffi.nim`. Polars is built
with `default-features = false` and `lazy`, `csv`, `fmt`, so only 32 and 64 bit
integers are compiled in.

## Goals / Non-Goals

**Goals:**
- A Nim type value that the rest of 0.2 (selectors, CSV schema overrides) can pass
  through the ABI.
- Room to add parameterized dtypes (Datetime with unit and zone, List with an inner
  type) in 0.3 and later without breaking user code.
- `cast` on expressions and frames with Polars' strict semantics.

**Non-Goals:**
- Temporal, nested, categorical and decimal dtypes (0.3 and 0.5 in the coverage map).
- Building or reading columns in widths other than int64 / float64 (use `cast`).
- Dtype selectors (`cs.numeric()`): they come with the column selectors change.

## Decisions

### `DataType` is an object variant with a kind enum
```nim
type
  DataTypeKind* = enum
    dkBoolean, dkInt8, dkInt16, dkInt32, dkInt64, dkUInt8, dkUInt16, dkUInt32,
    dkUInt64, dkFloat32, dkFloat64, dkString, dkNull, dkOther
  DataType* = object
    case kind*: DataTypeKind
    of dkOther: name*: string   # Polars' name, e.g. "date", "list[i64]"
    else: discard

const Int64* = DataType(kind: dkInt64)   # and so on for each primitive kind
```
`==` compares kinds (and the name for `dkOther`). `$` returns the Nim type name
(`int64`, `float32`, `bool`, `string`), `null` for `dkNull`, and Polars' name for
`dkOther`. The tables show the same names (see "Nim names in tables").

### Nim names in tables
- *HTML:* `toHtml` builds the dtype row itself, so it uses `$` on each column's
  `DataType`.
- *Text (`$df`):* Polars renders the table (comfy_table), with the dtype in the third
  header line of each column and no option to rename it. `nq_df_to_string` post-processes
  that string in Rust: for each column it replaces the dtype cell with the Nim name and,
  when the name is longer than the column, widens that column by the difference on every
  line (spaces in content lines, the border character in border lines, at the column's
  right edge). Rust knows each column's dtype and the table layout is fixed, so this is a
  string pass with no Polars internals. Elided columns (`…`) have no dtype cell and are
  skipped.
- *Alternative:* hide Polars' dtypes (`POLARS_FMT_TABLE_HIDE_COLUMN_DATA_TYPES`) and
  rename columns to `name\n---\nint64` in a cheap clone. Rejected: Polars measures and
  truncates the name as one string, so widths come out wrong.
- *Alternative:* Nanuq's own text renderer, like `toHtml`. More code to keep in line
  with Polars' cell formatting; worth it only if the post-processing proves fragile.
- *Why:* Polars' Rust `DataType` is an enum with data in some variants; an object
  variant is the Nim equivalent, and later kinds (`dkDatetime` with `unit` and `zone`,
  `dkList` with an `inner: ref DataType`) are added as new branches without changing
  existing code.
- *Alternative:* a plain enum `DataType`. Simplest today, but turning it into an object
  for Datetime or List would break every user of it.
- *Alternative:* a `ref object` hierarchy like Python's classes. More allocation and
  `of` checks, with no gain over a variant.
- Constants use Polars' names (`Int64`, `String`). They are exported from `nanuq`; a
  clash with a user symbol is resolved by qualifying, e.g. `nanuq.String`.

### Dtypes cross the ABI as a code
`#[repr(C)] enum NqDtype { Boolean = 0, Int8, ..., Null, Other }`, mirrored in
`ffi.nim` in the same order as `DataTypeKind`. `nq_df_column_dtype_kind(df, name) ->
i32` returns the code (or -1 on error). For `Other`, Nim also calls the existing
`nq_df_column_dtype` for the name. Casting passes a code; `Other` is rejected in Nim
before any call.
- *Why:* fits the existing enum style, and a code is enough until dtypes have
  parameters. A parameterized dtype will need a small struct or a string form (Polars
  can parse dtype strings); that is decided when the first one arrives.

### Schemas reuse DataFrame accessors
`schema(df)` loops over `columns(df)` and asks each dtype (one call per column, not per
row). `collectSchema(lf)` calls `nq_lf_collect_schema`, which resolves the plan's schema
(`LazyFrame::collect_schema`) and returns `DataFrame::empty_with_schema`; Nim then reads
it with `schema`. Nothing is computed beyond schema resolution.
- *Why:* no new type to free and no array-of-structs across the boundary.

### Cast functions
- `nq_expr_cast(e, code, strict: bool) -> *mut Expr` uses `strict_cast` or `cast` with
  non-strict options in Polars 0.55.
- `nq_lf_cast(lf, names, codes, n, strict) -> *mut LazyFrame` casts the named columns
  (`LazyFrame::cast` with a map). Casting all columns is done in Nim as
  `cast(all columns)` by passing every name from the schema, so one Rust function covers
  both forms. DataFrame versions are eager shortcuts over the lazy one, as for the other
  verbs.
- Nim names: `cast` (a keyword, usable with method-call syntax, see the proposal).

### Nim types as cast targets
`cast` has a `typedesc` overload next to the `DataType` one:
```nim
proc cast*(e: Expr, T: typedesc, strict = true): Expr = e.cast(dataType(T), strict)
```
`dataType(T)` is resolved at compile time (`when T is int8: Int8 ...`), and an
unsupported type (an object, `seq`) is a compile error. Named frame casts stay on
`DataType` (`{"a": Int32}`), because an `openArray` needs one element type and
typedescs exist only at compile time; `dataType(int32)` gives the same value.
- *Why:* reads already take Nim types (`toSeq(df, "a", int)`), so writes and casts should
  too; the Polars names stay available for run-time values.
- *Later:* `seq[T]` can map to List and `DateTime` to Datetime, with a `DataType` for the
  cases a Nim type can't express (time unit, time zone).

### ABI version during 0.2
`Cargo.toml` moves to `0.2.0-dev` with this change. `ffi.nim` already treats `-dev`
versions as development builds (no prebuilt download; local or cargo build). The other
0.2 changes keep `0.2.0-dev`, and `lib-v0.2.0` is released once, when 0.2 is complete,
so there is one release cycle for the whole slice instead of one per change.

## Risks / Trade-offs

- **Breaking `dtype`.** Comparisons with strings stop compiling (a `DataType` is not a
  string), which is loud rather than silent. Nanuq is pre-1.0 with no known users
  outside the repo; the CHANGELOG calls it out.
- **Binary size.** Four small dtype features add a little code to an already large
  static library. Accepted.
- **Constant names may shadow.** `String`, `Boolean`, `Null` are common words. Nim is
  case-sensitive on the first letter, so they do not clash with `string` or `bool`.
