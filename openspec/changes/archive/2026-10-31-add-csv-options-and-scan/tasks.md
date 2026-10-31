# Tasks

## 1. Bridge

- [x] 1.1 Add `nq_lf_scan_csv` with all read options (separator, header, nulls, overrides, skip rows, row limit, inference length, ignore errors, decimal comma); remove `nq_df_read_csv`
- [x] 1.2 Add `NqQuoteStyle` and the write options to `nq_df_write_csv`
- [x] 1.3 Mirror everything in `ffi.nim`; verify that `cargo build --release` passes

## 2. Nim API

- [x] 2.1 Add `scanCsv` with the read options, and make `readCsv` `scanCsv(...).collect` with the same options (`columns` as a select)
- [x] 2.2 Add `QuoteStyle` and the `writeCsv` options
- [x] 2.3 Accept a plain `int` (as `int | Option[int]`) for `nRows`, `inferSchemaLength` and `floatPrecision`
- [x] 2.4 Write `tests/test_csv.nim`: every option, a glob over two files, a glob whose files have different columns failing, `columns` projection, `schemaOverrides` and its `Other` error, and round trips (`;` with decimal comma, `quoteStyle = Always`, `nullValue`, `floatPrecision`); add it to `nanuq.nimble` and `.gitignore`

## 3. Docs and integration

- [x] 3.1 Document the CSV options in the README; verify that `nimble test`, `nimble example` and the existing CSV tests pass
- [x] 3.2 Check that CI is green on the PR, including the Rust rebuild

## Workflow follow-up

- Archive the change (`/opsx:archive`). Narrow the BACKLOG "More IO" entry to Parquet, JSON and `scanParquet`, and add CHANGELOG lines with the PR number.
