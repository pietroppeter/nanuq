# Proposal

## Why

The Arrow C Data Interface is the standard way to hand columns between libraries in one
process without copying: DuckDB, Arrow C++/GLib, nanoarrow and any Arrow-aware C library
read and write it. It is how Python Polars talks to PyArrow, pandas and DuckDB
(`to_arrow`, `from_arrow`, `__arrow_c_stream__`), and the 0.6 book map counts 7 sections
using it. It also gives Nim code zero-copy access to Polars' buffers, which is what the
BACKLOG.md entry "Zero-copy columns through the Arrow C Data Interface" asks for, to make
`mapElements` faster.

It is the fourth change of the 0.6 release and takes that BACKLOG.md entry.

## What Changes

- Nim objects with the standard layouts: `ArrowSchema`, `ArrowArray`,
  `ArrowArrayStream`, and `release` for each.
- `s.toArrow: ArrowExport` (schema + array, released when it goes away unless a
  consumer took them over) and `fromArrow(schema, array, name)` /
  `fromArrow(export)` for Series; `df.toArrow: ArrowArrayStream` and
  `fromArrow(stream)` for frames (record batches as struct arrays).
- `s.view(T)` / `df.view(column, T)`: a `ColumnView[T]` reading a numeric column without
  nulls in place (`v[i]`, `v.len`, `items`, `v.toOpenArray`).
- `mapElements` on numeric columns without nulls reads each batch through a view
  instead of copying it into a seq first.

## Capabilities

### New Capabilities
- `arrow-interop`: exchanging columns and frames through the Arrow C Data Interface, and
  zero-copy views.

## Differences from Polars

- Python returns PyArrow objects (`pa.Array`, `pa.Table`); Nanuq hands out the C
  structs themselves, which is what a Nim program passes to a C library. There is no
  `compat_level` argument: Nanuq always exports the newest layout (string views).
- `fromArrow` takes over the array (Arrow's move semantics); Python copies or shares
  through PyArrow.
- `view` has no Python counterpart besides `to_numpy(allow_copy = False)`, which it
  mirrors for numeric columns; it refuses columns with nulls instead of copying.

## Impact

- `src/rust/Cargo.toml`: `polars-arrow` (for its `ffi` module).
- `src/rust/src/lib.rs`, `src/nanuq/ffi.nim`: `nq_series_to_arrow`,
  `nq_series_from_arrow`, `nq_df_to_arrow_stream`, `nq_df_from_arrow_stream`, and the
  struct layouts.
- `src/nanuq.nim`: the API above and the `mapElements` fast path.
- New `tests/test_arrow.nim`; `benchmarks/map_elements` rerun.
