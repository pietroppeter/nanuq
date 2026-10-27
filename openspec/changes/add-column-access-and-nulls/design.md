# Design

## Context

Today `toSeq` loops over rows and calls `nq_df_get_{i64,f64,str}` once per cell. Each
call looks up the column, builds an `AnyValue` and checks the type. A null makes
`extract` fail, so the call returns an error. Series can only be built from plain
arrays. `nq_df_read_csv` uses `CsvReadOptions::default()` with a header and no null
markers. `NqUnary` is a `#[repr(C)]` enum mirrored in `ffi.nim`.

## Goals / Non-Goals

**Goals:**
- One FFI call per numeric or bool column and two per string column, whatever the
  height.
- No null is ever silently turned into a value (0, NaN, "").
- Keep the ABI style: borrow arguments, caller frees, errors through `nq_last_error`.

**Non-Goals:**
- Zero-copy. Values are still copied into Nim memory. Arrow C Data Interface sharing
  stays in the backlog.
- Dates, datetimes and other dtypes (still in the backlog).
- A null-aware `Series` read API. Reads go through DataFrame columns only, as today.

## Decisions

### Caller-allocated buffers for fixed-width columns
`nq_df_column_i64(df, name, values: *mut i64, valid: *mut bool, len) -> bool` (and
`_f64`, `_bool`). Nim allocates `height` slots in `seq[T]` and `seq[bool]` and passes
pointers. Rust casts the column to the target dtype (see the dtype rules below), checks
`len == height`, and fills both buffers in one pass over `chunked_array.iter()` (one
`Option<T>` per row).
- *Why:* Nim owns the memory, so there is no extra free function and no
  double-ownership risk. Filling is a single tight loop.
- *Alternative:* Rust allocates and returns a pointer plus a free function. That needs
  one more call and one more type to free, with no gain.
- *Alternative:* return values only, and signal nulls through a separate
  `null_count` / `is_null` call. That is not constant-call when there are nulls.

### Strings in two calls
`nq_df_column_str_size(df, name) -> i64` returns the total UTF-8 byte length (-1 on
error). `nq_df_column_str(df, name, data: *mut u8, data_len, offsets: *mut u64, valid:
*mut bool, len) -> bool` writes the concatenated bytes and `len + 1` offsets, which is
Arrow's string layout. Nim then slices `data` into strings. Nulls have equal
consecutive offsets and `valid = false`.
- *Why:* there is no per-string allocation across the boundary, and the layout matches
  Arrow, so moving to zero-copy later stays close.
- *Alternative:* return an array of C strings to free one by one. That costs N
  allocations and frees.

### Dtype rules on the Rust side
For float, Rust casts any numeric dtype to Float64. For string, it casts any dtype to
String. For int, it accepts only integer dtypes and casts them to Int64. For bool, it
requires Boolean. Anything else is an error naming the column and its dtype. Casting in
Rust reuses Polars' formatting and is a single vectorised operation.

### Strict vs Option in Nim
`toSeq(df, col, T)` calls the bulk function and raises `NanuqError` if any `valid[i]`
is false: "column 'a' has N nulls; read it as Option[T] or fill them first".
`toSeq(df, col, Option[T])` builds `some`/`none` from the mask. Both share one internal
`readColumn` per type returning `(values, valid)`. The single-cell `df[col, row,
Option[T]]` and `isNull` use a new `nq_df_is_null(df, name, row, out: *mut bool)`
together with the existing getters, because a single cell doesn't need the bulk path.
- *Why strict by default:* a null that silently becomes 0 is the bug this change is
  meant to prevent. Users who want defaults write `fillNull` in the query, or map over
  the Option seq.

### Building with nulls
`nq_series_new_{i64,f64,bool,str}_opt(name, data, valid, len)`. Rust builds
`Vec<Option<T>>` and `Series::new`. On the Nim side, `series(name, openArray[Option[T]])`
fills a values buffer (default value where `none`) and a mask.

### Expressions and dropNulls
- Append `IsNull` and `IsNotNull` to the end of `NqUnary`, so existing values keep
  their numbers, and mirror them in `ffi.nim`.
- `nq_expr_fill_null(e, value: *const Expr) -> *mut Expr`. In Nim, `fillNull` takes an
  `Expr` or a literal through `lit`, like the binary operators.
- `nq_lf_drop_nulls(lf, names: *const *const c_char, len) -> *mut LazyFrame`, where
  `len == 0` means all columns. It maps to `LazyFrame::drop_nulls(None | Some(selector))`.
  The DataFrame shortcut goes through `lazy`/`collect`, like the other eager methods.

### CSV null markers
`nq_df_read_csv` gains `null_values: *const *const c_char, len`. With `len == 0` it
behaves as today. Otherwise it sets `CsvParseOptions::with_null_values(
Some(NullValues::AllColumns(..)))`. In Nim, `readCsv(path, nullValues: openArray[string]
= [])` keeps today's calls source-compatible. The old one-argument C function is
replaced, which is fine because the Nim wrapper is the only caller.

## Risks / Trade-offs

- [Polars 0.55 API names, such as the `drop_nulls` selector type and the null-values
  option path, may differ from the above] → Check against the 0.55 docs while
  implementing; the behavior in the specs doesn't depend on them.
- [Changing `toSeq` to fail up front on nulls] → It already failed at the first null;
  only the timing and message change. Note it in the CHANGELOG.
- [Rust rebuild in CI costs about 10 min once] → Expected for any ABI change; the cache
  covers later runs.
- [The `ffi.nim` and `lib.rs` signatures drift apart] → Every new function gets a test
  that calls it through the Nim API.
