# Proposal

## Why

SQL is the most used API still missing from the book ports: `SQLContext.execute`
appears in 18 sections and `SQLContext` in 10, mostly the user guide's SQL chapters.
For users coming from SQL it is also the shortest way in. The coverage map lists it as one
bridge call behind the `sql` feature.

It is the sixth change of the 0.5 release.

## What Changes

- `SQLContext`: `newSQLContext()` or `newSQLContext({"bears": lf})`, `register`
  (LazyFrame or DataFrame), `unregister`, `tables`, and `execute(query)` giving a
  LazyFrame (or a DataFrame with `eager = true`).
- `sqlContext(bears, dens)`, a macro that registers frames under their variable names
  (what Python's `register_globals` and keyword arguments do).
- `lf.sql(query, tableName = "self")` and `df.sql(...)`, and `sql(query, frames)`.
- SQL table functions (`read_csv`, `read_parquet`, `read_ipc`, `read_json`) work in
  queries.

## Capabilities

### New Capabilities
- `sql`: running SQL queries on frames.

## Differences from Polars

- No `register_globals` (Nim cannot list a scope's variables at run time); the
  `sqlContext(a, b)` macro names frames after the variables passed to it instead.
- `execute` returns a LazyFrame unless `eager = true`, as in Python; `df.sql` returns a
  DataFrame, `lf.sql` a LazyFrame.
- No `register_many` with a dict: `newSQLContext` and `register` take `{"name": frame}`.

## Impact

- `src/rust/src/lib.rs` and `src/nanuq/ffi.nim`: `nq_sql_*` functions on an opaque context.
- `src/nanuq.nim`: `SQLContext` and helpers.
- New `tests/test_sql.nim`.
