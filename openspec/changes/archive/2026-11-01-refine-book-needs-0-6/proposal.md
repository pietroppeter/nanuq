# Proposal

## Why

The book ports against the 0.6 branch (round 3) found two mismatches with Python:
`readExcel(skipRows = 1)` skipped rows before the header, while py-polars' default
engine (fastexcel) skips them after it (O'Reilly's top2000 workbook has an empty row
under its header); and `rolling(..., groupBy = "store")` did not compile.

It is the eleventh change of the 0.6 release.

## What Changes

- `readExcel` and `readExcelSheets`: `skipRows` skips rows after the header row;
  new `headerRow` (from 0) says which row holds the names. Without a header,
  `skipRows` still skips from the top. **Breaking** only against the unreleased 0.6 branch.
- `rolling` and `groupByDynamic`: `groupBy` takes names or expressions (`GroupKeys`).

## Capabilities

### Modified Capabilities
- `excel-io`: Reading Excel (header row and skipped rows).
- `temporal-grouping`: group keys by name.

## Differences from Polars

- Python passes these as `read_options={"header_row": ..., "skip_rows": ...}`; Nanuq
  has them as parameters, `headerRow` and `skipRows`.

## Impact

- `src/rust/src/lib.rs` (`nq_read_excel` gains `header_row`), `src/nanuq/ffi.nim`,
  `src/nanuq.nim`; tests in `tests/test_bookneeds6.nim`.
