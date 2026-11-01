# Proposal

## Why

CSV is the only format Nanuq reads and writes. Parquet is what most data arrives in
today and what Polars is fastest with; Arrow IPC (Feather v2) is the format other Arrow
tools exchange without conversion. Both keep dtypes, which CSV loses: a Date column
written to CSV comes back as a string. Reading from a Nim `Stream` lets a program parse
data it already holds in memory (a download, an embedded table, a test fixture) without
a temporary file.

This change takes up the BACKLOG.md entry "More IO" (Parquet and IPC) and follows the
dev log "Designing Nanuq 0.3", section 5. It is the sixth change of the 0.3 release.

## What Changes

- **Parquet**: `scanParquet(path, nRows, columns, rowIndexName, rowIndexOffset,
  lowMemory)` (a file or glob), `readParquet(path or Stream, ...)` and
  `writeParquet(df, path, compression = ParquetCompression.Zstd, compressionLevel =
  none(int), statistics = true, rowGroupSize = none(int))`. `ParquetCompression` is a
  pure enum: `Lz4`, `Uncompressed`, `Snappy`, `Gzip`, `Brotli`, `Zstd`.
- **IPC**: `scanIpc`, `readIpc(path or Stream, ...)` with the same read options, and
  `writeIpc(df, path, compression = IpcCompression.Uncompressed)`, with
  `IpcCompression` `Uncompressed`, `Lz4`, `Zstd`.
- **Streams**: `readCsv(stream, ...)` with every CSV read option.
- Hive partitions are detected as in Polars' default for paths; in-memory bytes never
  are.
- Polars features `parquet` and `ipc` (already compiled in by the string change) are
  used.

Not in this change: writing to a stream or a string, cloud storage, `sinkParquet`
and the other sink functions (streaming writes), Parquet `useStatistics`, `parallel`
and hive options, `readParquetSchema`, IPC streams (`readIpcStream`), NDJSON and Excel.

## Capabilities

### New Capabilities
- `parquet-ipc`: reading and writing Parquet and Arrow IPC files and bytes.

### Modified Capabilities
- `csv-io`: reading CSV from a stream.
- `native-bridge`: `NqParquetCompression` and `NqIpcCompression` join the ordered enums;
  `nq_lf_scan_csv` takes optional in-memory bytes.

## Differences from Polars

Expected differences from Polars' Rust and Python APIs:

- **Streams**: Python reads any file-like object or `bytes`; Rust uses readers over
  `Cursor`s. Nanuq reads a Nim `Stream`, all of it, when `readCsv`/`readParquet`/
  `readIpc` is called. The `scan*` procs take paths only.
- **Compression** is a pure enum instead of Python's strings (`"zstd"`) and Rust's enum
  with the level inside (`Zstd(Some(ZstdLevel))`); the level is a separate
  `compressionLevel`, as in Python. A level with a codec that has none raises
  `ValueError` (Python ignores it).
- **`statistics`** is a bool (Python also takes `"full"` or a dict).
- **`IpcCompression`** has `Uncompressed` as a value (Python's `"uncompressed"`; Rust uses
  `None`).
- **Names** follow Polars in camelCase: `row_index_name` → `rowIndexName`,
  `compression_level` → `compressionLevel`, `row_group_size` → `rowGroupSize`.

## Impact

- `src/rust/src/lib.rs`: `nq_lf_scan_parquet`, `nq_lf_scan_ipc`, `nq_df_write_parquet`,
  `nq_df_write_ipc`, the two compression enums, and bytes for `nq_lf_scan_csv`.
- `src/nanuq/ffi.nim`, `src/nanuq.nim`: the declarations and procs; `nanuq` imports
  `std/streams`.
- `tests/test_io.nim` (new); README; BACKLOG "More IO" keeps the remaining formats.
