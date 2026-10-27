# Tasks

## 1. Bulk column reads

- [x] 1.1 Add `nq_df_column_{i64,f64,bool}` with caller-allocated values and validity buffers and the dtype rules from design.md, and mirror them in `ffi.nim`; verify `cargo build --release` passes
- [x] 1.2 Add `nq_df_column_str_size` and `nq_df_column_str` (bytes, offsets, validity), and mirror them in `ffi.nim`; verify `cargo build --release` passes
- [x] 1.3 Reimplement `toSeq(df, col, T)` for int, float, bool and string on the bulk path, raising `NanuqError` naming the column when there are nulls; verify the existing tests still pass and new tests cover int→float, float→int error, bool and any→string

## 2. Reading and inspecting nulls

- [x] 2.1 Add `toSeq(df, col, Option[T])` from the validity mask; verify with a test on a column 1, null, 3
- [x] 2.2 Add `nq_df_null_count` and `nq_df_cell_is_null`, plus `nullCount`, `hasNulls` and `df[col, row, Option[T]]` in Nim; verify with tests
- [x] 2.3 Add `nq_series_new_*_opt` and `series(name, openArray[Option[T]])` for the four types; verify a round-trip test (build with nulls, read back as Option, `dtype` unchanged)

## 3. Nulls in queries and IO

- [x] 3.1 Append `IsNull` and `IsNotNull` to `NqUnary` in Rust and `ffi.nim`, and add `isNull` / `isNotNull` on Expr; verify with a filter test
- [x] 3.2 Add `nq_expr_fill_null` and `fillNull` (Expr or literal); verify with a test
- [x] 3.3 Add `nq_lf_drop_nulls` and `dropNulls` on LazyFrame and DataFrame (all columns or a subset); verify with tests for both forms
- [x] 3.4 Add null markers to `nq_df_read_csv` and `readCsv(path, nullValues = [])`; add `tests/data/with_na.csv` with "NA" fields; verify that a numeric column with NA reads as f64/i64 with nulls, and that calling without `nullValues` behaves as before

## 4. Docs and integration

- [x] 4.1 Update README "What is there" and the `toSeq` doc comments for Option reads, `nullCount`, `hasNulls`, `fillNull`, `dropNulls` and `nullValues`; verify `nimble test` and `nimble example` pass
- [ ] 4.2 Check that CI is green on the PR, including the one-off Rust rebuild

## Workflow follow-up

- Archive the change (`/opsx:archive`): remove the "Column access as Nim seqs" entry and the nulls part of "Nulls and more dtypes" from BACKLOG.md (dates stay), and add a CHANGELOG line with the PR number, mentioning that `toSeq` now fails up front on columns with nulls.
- Next: the penguins dataset (Datasets in BACKLOG.md) can then load the full file with `nullValues = @["NA"]`.
