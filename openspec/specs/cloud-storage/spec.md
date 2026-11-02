# cloud-storage Specification

## Purpose
Reading and writing object stores (S3, Google Cloud Storage, Azure, HTTP) by URI, with Python's storage options.

## Requirements

### Requirement: Cloud URIs
Every `scan*` and `read*` function for CSV, Parquet, IPC and NDJSON files SHALL accept a
cloud URI (`s3://`, `gs://`, `az://`, `abfss://`, `hf://`, `http://`, `https://`) in place
of a local path, globs included. `isCloudPath(path)` SHALL tell such URIs from local
paths.

```nim
echo isCloudPath("s3://polar-bears/census.parquet")
echo isCloudPath("https://example.org/bears.csv")
echo isCloudPath("data/bears.csv")
```

```text
true
true
false
```

#### Scenario: HTTP
- **WHEN** `readParquet("http://127.0.0.1:<port>/bears.parquet")` runs against a local
  HTTP server
- **THEN** the frame equals the file's

### Requirement: Storage options
The cloud-capable reads, scans, writes and sinks SHALL take `storageOptions`, key/value
pairs as Python's `storage_options` (`aws_region`, `aws_endpoint_url`,
`google_service_account`, `azure_storage_account_name`, ...). Without them, credentials
SHALL come from the environment as in Polars. Unknown keys SHALL be ignored, as in
Polars; a failed request SHALL raise `IOError`.

```nim
let opts = {"aws_region": "eu-west-1", "aws_skip_signature": "true"}
let lf = scanParquet("s3://polar-bears/census.parquet", storageOptions = opts)
echo lf is LazyFrame
```

```text
true
```

#### Scenario: Missing bucket
- **WHEN** `readParquet("s3://no-such-bucket/x.parquet", storageOptions = opts)` runs
  against a local S3
- **THEN** `IOError` is raised

### Requirement: Writing to object stores
`writeParquet`, `writeCsv`, `writeIpc`, `writeNdjson` and the sinks (also partitioned)
SHALL write to a cloud URI, with `storageOptions`; the eager writes SHALL go through a
streaming sink.

```nim
let df = newDataFrame(series("bear", @["Ada", "Bo"]), series("kg", @[410, 380]))
let opts = {"aws_endpoint_url": "http://127.0.0.1:9000", "aws_allow_http": "true"}
let sink = df.lazy.sinkParquet("s3://polar-bears/out.parquet", lazy = true,
                               storageOptions = opts)
echo sink is LazyFrame  # collect(sink) writes the file
```

```text
true
```

#### Scenario: S3 round trip
- **WHEN** a frame is written to `s3://nanuq/bears.parquet` on a local S3 (moto) and read
  back with the same `storageOptions`
- **THEN** the frames are equal
