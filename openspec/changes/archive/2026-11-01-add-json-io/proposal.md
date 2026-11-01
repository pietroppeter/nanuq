# Proposal

## Why

JSON is the most common nested data format: `read_json` blocks 7 book sections and
`scan_ndjson`/`read_ndjson` 7 more, and the coverage map says JSON is useful once nested
dtypes exist, which they now do. It comes from the BACKLOG.md entry "More IO" (NDJSON;
Excel, sinks and cloud storage stay there).

It is the fifth change of the 0.5 release.

## What Changes

- `readJson(path or Stream)`: a JSON array of objects (or an object of columns).
- `readNdjson(path or Stream)` and `scanNdjson(path)`: newline-delimited JSON, one
  object per line, eager and lazy (globs, `nRows`, row index).
- Both take `schema` (all columns) or `schemaOverrides` (some), `inferSchemaLength` and
  `ignoreErrors`.
- `writeJson(path or Stream)` writes a JSON array of row objects, `writeNdjson` one
  object per line; `toJson`/`toNdjson` give the text.

## Capabilities

### New Capabilities
- `json-io`: reading and writing JSON and NDJSON.

## Differences from Polars

- Python's `write_json()` without a file returns the text; Nanuq has `toJson` for that,
  so `writeJson` always writes.
- `schema` and `schemaOverrides` are `{"name": dtype}` pairs, as in `readCsv`.
- No cloud storage options.

## Impact

- `src/rust/src/lib.rs` and `src/nanuq/ffi.nim`: `nq_df_read_json`, `nq_lf_scan_ndjson`,
  `nq_df_write_json`.
- `src/nanuq.nim`: the readers and writers.
- New `tests/test_json.nim`.
