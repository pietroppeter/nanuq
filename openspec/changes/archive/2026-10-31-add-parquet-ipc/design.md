# Design

## One scan per format, paths or bytes

Every reader goes through a lazy scan in Rust, which takes either a path (file or glob)
or a byte buffer (`ScanSources::Buffers`). Eager `read*` procs are `scan*(...).collect`,
and the `Stream` overloads read the stream into a string and pass its bytes, which Rust
copies. One code path per format keeps the options identical for files and streams.

## Columns are a projection

`columns` becomes a `select` after the scan, as in `scanCsv`; Polars pushes it down into
the reader, so unread columns are never decoded.

## Hive partitions

Polars' Rust default enables hive partitioning, Python's detects it (`None`). Nanuq uses
Python's behaviour for paths. Polars does not implement hive partitioning for in-memory
buffers, so it is disabled there.
