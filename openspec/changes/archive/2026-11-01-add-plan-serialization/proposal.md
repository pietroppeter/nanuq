# Proposal

## Why

A serialized query plan can be stored, sent to another process or machine and run
there; Python Polars uses it for Polars Cloud and for caching plans. The roadmap lists
plan serialization and the rest of the `meta` namespace in 0.6 ("Engine and edges"). 0.5
added only `meta.outputName`, `rootNames`, `hasMultipleOutputs`, `isColumn` and
`isLiteral`.

It is the second change of the 0.6 release.

## What Changes

- `SerializationFormat` enum (`Binary`, `Json`).
- `lf.serialize(format = Binary): string` and `lf.serialize(path, format)`;
  `deserialize(LazyFrame, data, format)` and `deserializeFile(LazyFrame, path, format)`.
  The plan keeps in-memory frames, so a serialized eager frame's query carries its data.
- `e.meta.serialize(format)` and `deserialize(Expr, data, format)`.
- More of `meta`: `eq`, `ne`, `pop`, `isRegexProjection`,
  `isColumnSelection(allowAliasing)`, `isLiteral(allowAliasing)`, `treeFormat`.

## Capabilities

### New Capabilities
- `plan-serialization`: serializing LazyFrames and expressions.

## Differences from Polars

- Binary data is returned as a Nim `string` of bytes (Python `bytes`), and a file is
  written by an overload taking a path (Python's `file` argument).
- Python's classmethods `pl.LazyFrame.deserialize(source)` and `pl.Expr.deserialize`
  become `deserialize(LazyFrame, data)` and `deserialize(Expr, data)`; reading a file is
  `deserializeFile`.
- Plans contain Nim callbacks (`mapElements`, `mapBatches`, ...) as function pointers,
  which cannot be serialized: serializing them raises `ComputeError` (Python pickles
  the Python function).
- Plans written by Nanuq (Rust Polars 0.55.2) and by py-polars are only compatible when
  their plan format version (`DSL_VERSION`) matches.
- No `DataFrame.serialize`; use `writeIpc`/`writeParquet`, or `df.lazy.serialize`.
- `treeFormat` returns the text; there is no `return_as_string = false` printing mode.

## Impact

- `src/rust/Cargo.toml`: Polars features `serde`, `serde-lazy`; `serde_json` and
  `polars-utils` (for Polars' binary expression format).
- `src/rust/src/lib.rs`, `src/nanuq/ffi.nim`: `nq_lf_serialize`, `nq_lf_deserialize`,
  `nq_expr_serialize`, `nq_expr_deserialize`, more `meta` operations.
- New `tests/test_serialization.nim`.
