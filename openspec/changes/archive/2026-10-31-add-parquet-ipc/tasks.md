# Tasks

## 1. Bridge

- [x] 1.1 Add `nq_lf_scan_parquet`, `nq_lf_scan_ipc`, `nq_df_write_parquet` and `nq_df_write_ipc` with the compression enums
- [x] 1.2 Let `nq_lf_scan_csv` read in-memory bytes; mirror everything in `ffi.nim`

## 2. Nim API

- [x] 2.1 Add `ParquetCompression`, `IpcCompression`, `scanParquet`, `readParquet`, `writeParquet`, `scanIpc`, `readIpc` and `writeIpc`
- [x] 2.2 Add the `Stream` overloads of `readCsv`, `readParquet` and `readIpc`
- [x] 2.3 Write `tests/test_io.nim`; add it to `nanuq.nimble` and `.gitignore`

## 3. Docs and integration

- [x] 3.1 README lists the formats; `nimble test` and `nimble specexamples` pass
- [x] 3.2 Archive the change: update BACKLOG "More IO", add CHANGELOG lines
