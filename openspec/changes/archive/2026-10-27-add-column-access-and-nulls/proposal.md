# Proposal

## Why

Getting data out of Nanuq is slow and incomplete. `toSeq` makes one FFI call per cell,
and nothing can represent a missing value: reading a null raises, and Nim data with
gaps can't be built at all. Most of the backlog is blocked on this. That includes
penguins (it has NAs), the ggplotnim module, Datamancer and Arraymancer interop, and
nimib tables. Polars also works with nulls everywhere, so the API should expose them
before outside users arrive.

This change takes up two BACKLOG.md entries: "Column access as Nim seqs without
per-cell calls" (API) and the nulls half of "Nulls and more dtypes" (API). Dates and
datetimes stay in the backlog.

## What Changes

- Whole columns cross the boundary in **one FFI call** (two for strings), with a validity
  mask, for int64, float64, bool and string.
- `toSeq(df, col, T)` uses the bulk path. It **raises `NanuqError` if the column has
  nulls**; today it raises too, but only when it reaches the first null.
- New `toSeq(df, col, Option[T])` returns `seq[Option[T]]`, with `none` for nulls.
- New null-aware single cells: `df[col, row, Option[T]]`.
- New `nullCount(df, col)` and `hasNulls(df, col)`.
- New `series(name, openArray[Option[T]])` builds columns with nulls from Nim.
- `readCsv` gains `nullValues` (e.g. `@["NA"]`), so files like penguins load with real
  nulls instead of the string `"NA"`.
- New expressions `isNull`, `isNotNull` and `fillNull(value)`, and `dropNulls` on
  LazyFrame and DataFrame (all columns, or a subset).
- Reading a column as `float` accepts integer columns, and reading it as `string`
  accepts any dtype. Reading as `int` stays strict, so floats are not truncated.

## Capabilities

### New Capabilities
- `missing-values`: how nulls are represented, built, read, tested, filled and dropped
  in the Nim API.

### Modified Capabilities
- `dataframe-api`: the "Building and reading data" requirement now covers bulk column
  reads, the dtype rules for reading, and `readCsv` null markers.
- `native-bridge`: a new requirement that columns cross the C ABI in bulk with a
  validity mask, not cell by cell.

## Differences from Polars

Expected differences from Polars' Rust and Python APIs:

- **Strict reads.** Python's `Series.to_list()` returns `None` for nulls, and
  `to_numpy()` turns an integer column with nulls into floats with NaN. Nim's static
  types can't hold `None` in a `seq[int]`, so `toSeq(df, col, T)` raises on nulls, and
  `Option[T]` is the explicit opt-in. This is closest to Rust's `cont_slice()`, which
  errors when there are nulls.
- **No NaN for nulls.** Like Polars, Nanuq keeps NaN (a float value) and null (missing)
  distinct. It never converts one into the other the way `to_numpy()` does.
- **Per-column counts.** `nullCount(df, col)` and `hasNulls(df, col)` take a column
  name. Python's `DataFrame.null_count()` returns a one-row DataFrame with a count per
  column, and isn't added here.
- **Cell access.** Polars has no cell-level null test; Python's `df[row, col]` returns
  `None`. Nanuq's equivalent is `df[col, row, Option[T]]`.
- **Names** follow Polars in camelCase: `is_null` → `isNull`, `is_not_null` →
  `isNotNull`, `fill_null` → `fillNull`, `drop_nulls` → `dropNulls`, `null_count` →
  `nullCount`, `has_nulls` → `hasNulls`, `null_values` → `nullValues`.

## Impact

- `rust/src/lib.rs`: new column export functions (`nq_df_column_{i64,f64,bool}`, a
  two-step string export), `nq_series_new_*` variants with validity, `nq_df_null_count`,
  `nq_df_cell_is_null`, `nq_df_read_csv` with null values, `nq_expr_fill_null`, `nq_lf_drop_nulls`, and
  `IsNull` / `IsNotNull` appended to `NqUnary`. Adding the enum values at the end keeps
  the existing order. The Rust library is rebuilt, so the first CI run takes about 10 min.
- `src/nanuq/ffi.nim` and `src/nanuq.nim`: the matching declarations and API. Imports
  `std/options`.
- `tests/`: new tests for nulls and bulk reads, plus a small CSV fixture with NA values.
- The per-cell getters stay and keep their behavior. Nothing that works today breaks,
  except that `toSeq` on a column with nulls now fails up front.
