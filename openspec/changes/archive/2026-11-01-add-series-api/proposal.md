# Proposal

## Why

Polars users reach for a single column all the time: `df["oni"].max()`,
`(s - s.mean()) / s.std()`, `s.value_counts()`. In Nanuq a `Series` is only a way to
build a frame; there is no way to get one back, so every question about one column needs
`select` and `toList`. The coverage map put "a real Series" at the head of 0.4, and the
user guide's "Series" snippets and Packt's chapter 1 lean on it.

Polars itself is moving towards expressions everywhere, and Series methods in py-polars
are mostly thin wrappers that evaluate an expression. Nanuq can do the same: a Series
method runs the expression of the same name on a one-column frame. This adds the whole
Series surface with almost no new ABI.

It is the eighth change of the 0.4 release.

## What Changes

- **Getting a Series**: `df["name"]`, `df.getColumn("name")`, `df.toSeries(index)`.
- **Inspecting it**: `name`, `len`, `dtype`, `nullCount`, `$` (Polars' Series display),
  `toList(T)`, `s[i, T]`, `item(T)`, `toFrame`, `alias`/`rename`, `cast`, `describe`,
  `valueCounts`.
- **Operating on it**: arithmetic and comparison operators with literals and other
  Series, `filter(mask)`, and every expression method that takes no other column
  (aggregations, math, cumulative, rolling, ranking, distinct values, recoding, binning:
  `s.rollingMean(3)`, `s.cut([0.0])`), each evaluated through the expression of the same
  name. `eval(s, expr)` runs any expression on a Series.
- **Back into frames**: `df.withColumns(series)` and `lit(series)` in expressions.

## Capabilities

### New Capabilities
- `series`: getting, inspecting and operating on single columns.

## Differences from Polars

- Aggregations return a Series of one value (`s.sum`), read with `item(T)`
  (`s.sum.item(float)`); Python returns a Python scalar. Nim needs the type at compile
  time, and keeping a Series lets aggregations chain.
- A Series does not convert to an expression automatically: use `lit(s)` (Python accepts
  a Series wherever an expression goes).
- Series methods that would take other columns (`sortBy`, `topKBy`, `interpolateBy`,
  `over`) are not forwarded; use a frame.
- No in-place methods (`append`, `extend`, `set`, `scatter`): Nanuq values are immutable.

## Impact

- `src/rust/src/lib.rs`: `nq_df_get_column`, `nq_df_to_series`, `nq_series_to_frame`,
  `nq_series_name`, `nq_series_len`, `nq_series_rename`, `nq_series_to_string`;
  `src/nanuq/ffi.nim`; `src/nanuq.nim` (the forwarding macro).
- New `tests/test_series.nim`.
