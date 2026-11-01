# Proposal

## Why

Polars reads and writes object stores (S3, Google Cloud Storage, Azure, plain HTTPS) by
URI, and the book and explainers use public datasets that live there. The cost thread
("Weigh adding cloud storage to 0.6", https://claude.ai/artifact/F1haAENdb2wY6NGzJpQfab)
measured the Polars features `cloud`, `aws`, `gcp`, `azure` and `http` at about +2% of the
library (object_store, tokio, reqwest and rustls are already compiled in for streaming),
and found HTTPS reads already working. Pietro asked for it in 0.6, with the databases and
Excel (2026-11-01).

It is the fourteenth change of the 0.6 release.

## What Changes

- Polars features `cloud`, `aws`, `gcp`, `azure`, `http`.
- `storageOptions: openArray[(string, string)]` (Python's `storage_options`) on
  `scanCsv`, `readCsv`, `scanParquet`, `readParquet`, `scanIpc`, `readIpc`,
  `scanNdjson`, `readNdjson`, on the four sinks (also partitioned), and on `writeCsv`,
  `writeParquet`, `writeIpc`, `writeNdjson`. Empty options leave credentials to the
  environment (`AWS_*`, `GOOGLE_*`, `AZURE_*` variables, config files), as in Polars.
- Writes to a cloud URI run through a sink (the eager writers write local files).
- `isCloudPath(path)`.

## Capabilities

### New Capabilities
- `cloud-storage`: cloud URIs, storage options, writing to object stores.

## Differences from Polars

| Nanuq | Python | Rust (py-2.1.0) |
|---|---|---|
| `storageOptions = {"aws_region": "eu-west-1"}` | `storage_options={"aws_region": ...}` | `CloudOptions::from_untyped_config` |
| `writeParquet("s3://...")` | `write_parquet("s3://...")` | `sink` with `cloud_options` |
| `isCloudPath` | (internal `_is_supported_cloud`) | `CloudScheme::from_path` |

- No `credential_provider` (Python's callable that refreshes credentials) and no
  `retries` argument; retries can go in `storageOptions` (`max_retries`).
- `readExcel`, `readJson` and `readDatabase` stay local.

## Impact

- `src/rust/Cargo.toml` features; `src/rust/src/lib.rs`: `nq_cloud_options_new`,
  `nq_cloud_options_free`, a `cloud_options` argument on the four scans and in
  `NqSinkOptions`.
- `src/nanuq.nim`, `src/nanuq/ffi.nim`; new `tests/test_cloud.nim` (a local HTTP server,
  and a local S3 with moto when `moto_server` is installed; CI installs it).
- `docs/coverage/polars.json`: the cloud row becomes covered.
