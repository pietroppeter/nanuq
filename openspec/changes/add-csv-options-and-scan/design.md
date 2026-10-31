# Design

## Context

`readCsv` calls `nq_df_read_csv(path, null_values, n)`, which uses the eager
`CsvReadOptions` reader. `writeCsv` calls `nq_df_write_csv(df, path)` with `CsvWriter`
defaults. Polars 0.55 has `LazyCsvReader::new(path)` with `with_separator`,
`with_has_header`, `with_null_values`, `with_dtype_overwrite`, `with_skip_rows`,
`with_n_rows`, `with_infer_schema_length`, `with_ignore_errors`, `with_decimal_comma` and
`with_glob` (on by default), ending in `.finish()`. `CsvWriter` has `with_separator`,
`include_header`, `with_null_value`, `with_quote_style(QuoteStyle)`,
`with_float_precision` and `with_decimal_comma`.

## Goals / Non-Goals

**Goals:**
- One reader in Rust for both eager and lazy reads, so their behavior can't drift.
- The option set the 0.2 explainer needs, with Polars' defaults.

**Non-Goals:**
- Every Python option. The rest come when someone needs them.
- An options object. Pietro chose named arguments, and an object overload can be added
  later.

## Decisions

### One scan function
```rust
nq_lf_scan_csv(path, separator: u8, has_header: bool,
               null_values: *const *const c_char, n_nulls: usize,
               override_names: *const *const c_char, override_dtypes: *const NqDtype,
               n_overrides: usize, skip_rows: usize, n_rows: i64 /* <0: all */,
               infer_schema_length: i64 /* <0: all rows */, ignore_errors: bool,
               decimal_comma: bool) -> *mut LazyFrame
```
`readCsv` is `scanCsv(...).collect` in Nim, and `columns` becomes a `select` after the
scan, which Polars pushes down into the reader. `nq_df_read_csv` is removed. That is
fine within `0.2.0-dev`.
- *Why:* one code path and one ABI function. The lazy plan gives projection pushdown
  for free.
- *Alternative:* keep an eager reader with its own options. That duplicates the options
  for a small speed gain on tiny files.

### Separator as `char`
Nim's `char` is one byte, the same as Rust's `u8`. A non-ASCII `char` literal cannot be
written, so no runtime check is needed.

### Overrides as `DataType`
`schemaOverrides: openArray[(string, DataType)]` goes across as names plus `NqDtype` codes,
the same encoding as `cast`. An `Other` dtype raises `NanuqError`.

### Optional integers
`Option[int]` parameters cross as `-1` for none. Plain-`int` overloads wrap in `some`. The
number of overloads stays small, because only `nRows` and `inferSchemaLength` (read) and
`floatPrecision` (write) are optional integers. A template generates the plain-`int`
variants.

### `writeCsv`
`nq_df_write_csv(df, path, separator, include_header, null_value, quote_style:
NqQuoteStyle, float_precision: i32 /* <0: none */, decimal_comma) -> bool`.

## Risks / Trade-offs

- `readCsv` through the lazy engine changes error messages for some malformed files. The
  tests keep the existing CSV tests passing.
- Globs that match files with different columns fail. The proposal documents this, and
  the post uses diagonal concat.
