# Proposal

## Why

Data arrives wide or long, and analysis wants the other shape: NOAA publishes its El
Niño index as one row per year with twelve season columns, a spreadsheet keeps one column
per month, and a report wants the stations as columns. Nanuq can't reshape at all:
pivot was dropped from 0.3, and the book ports stop on `unpivot`, `pivot` and
`transpose` (O'Reilly chapters 4, 9 and 17, the user guide's "Pivots" and "Unpivots"
pages), and on `partition_by` (O'Reilly chapter 1, "Load").

It is the sixth change of the 0.4 release.

## What Changes

- **`pivot`** on DataFrame (finds the new columns itself, in order of appearance or
  sorted with `sortColumns`) and on LazyFrame (with the new columns given in
  `onColumns`), with `index`, `values`, `aggregateFunction` (a `PivotAgg` pure enum or
  an expression on `element()`), `maintainOrder` and `separator`.
- **`unpivot`** on DataFrame and LazyFrame, with `on`, `index`, `variableName` and
  `valueName`.
- **`transpose`** with `includeHeader`, `headerName` and `columnNames`.
- **`partitionBy`** returning a `seq[DataFrame]`, with `maintainOrder` and `includeKey`.
- **`toDummies`** with `columns`, `separator`, `dropFirst` and `dropNulls`.
- `ColumnNames`, a parameter type that takes one name or a list (`index = "year"` or
  `index = ["year", "month"]`), `element()` and `Expr.item(allowEmpty)`.

## Capabilities

### New Capabilities
- `reshaping`: pivot, unpivot, transpose, partitionBy, toDummies.

## Differences from Polars

- `aggregateFunction` is the `PivotAgg` pure enum (`Item`, `First`, `Last`, `Sum`,
  `Mean`, `Median`, `Min`, `Max`, `Len`) or an expression; Python takes strings or an
  expression and None, which Nanuq spells `Item` (the default, at most one value per
  cell).
- `index`, `values` and `on` take names (one or a list), not selectors.
- `partitionBy` has no `as_dict`; the frames come in a `seq` in order of appearance.
- `column_naming` is always Polars' "auto".

## Impact

- `src/rust/src/lib.rs`: `nq_lf_pivot`, `nq_lf_unpivot`, `nq_df_transpose`,
  `nq_df_partition_by`, `nq_df_array_free`, `nq_df_to_dummies`, `nq_expr_element`,
  `nq_expr_item`; `src/nanuq/ffi.nim`, `src/nanuq.nim`.
- New `tests/test_reshaping.nim`.
