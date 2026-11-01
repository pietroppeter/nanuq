# Proposal

## Why

Polars' streaming engine runs a query in batches, so it can process data larger than
memory, and sinks write a query's result straight to files without collecting it first.
The coverage roadmap puts both first in 0.6 ("Engine and edges"), the 0.6 book map needs
`sink_csv` (Packt ch2) and the user guide's streaming page, and BACKLOG.md "More IO"
names sink functions. The crate already compiles the streaming engine (the `json`
feature pulls it in), so this is a thin layer.

It is the first change of the 0.6 release. It takes the "sink functions" part of the
BACKLOG.md entry "More IO".

## What Changes

- `Engine` enum (`Auto`, `InMemory`, `Streaming`) and `collect(lf, engine)`,
  `collectAll(lfs, engine)`.
- `sinkParquet`, `sinkIpc`, `sinkCsv`, `sinkNdjson` on LazyFrames, with the options of
  the matching `write*` procs plus `maintainOrder` and `mkdir`. They run the query with
  the streaming engine and write the file; with `lazy = true` they return the sink plan
  as a LazyFrame instead, to run later with `collect` or several at once with
  `collectAll`.
- `PartitionBy(basePath, key, includeKey, maxRowsPerFile)` as the target of a sink
  writes one file per key value (Hive-style directories) or per row count.
- `profile(lf)` returns the result and a frame of node timings.

## Capabilities

### New Capabilities
- `streaming`: the streaming engine, sinks and query profiling.

## Differences from Polars

- `Engine` has no `Gpu` (Python only, through cuDF).
- `lazy` is a `static bool`: `sinkParquet(path)` returns nothing, `sinkParquet(path,
  lazy = true)` returns a LazyFrame (Python returns `None` or a LazyFrame from the same
  call).
- No cloud targets (`storage_options`, `credential_provider`, `retries`), no
  `sync_on_close`, no Parquet `metadata` or `field_overwrites`, no `optimizations`
  argument. `PartitionBy` has no `file_path` callback and no `approximate_bytes_per_file`.
- Python's `profile` can also show a plot; Nanuq returns the two frames.

## Impact

- `src/rust/src/lib.rs`, `src/nanuq/ffi.nim`: `nq_lf_collect_engine`, `nq_lf_sink`,
  `nq_lf_profile`, engine argument on `nq_collect_all`.
- `src/nanuq.nim`: the procs above.
- New `tests/test_streaming.nim`.
