# Spec Delta

## ADDED Requirements

### Requirement: Reading Parquet
The API SHALL provide `scanParquet(path, ...)`, a lazy scan of a file or a glob, and
`readParquet(path, ...)`, which is `scanParquet(...).collect`. Both SHALL take `nRows`,
`columns`, `rowIndexName` with `rowIndexOffset = 0`, and `lowMemory = false`. Every
dtype Nanuq models SHALL round-trip through Parquet unchanged.

```nim
let path = getTempDir() / "riders.parquet"
let df = newDataFrame:
  rider: ["Seixas", "Pogačar", "Evenepoel"]
  born: [date(2006, 9, 24), date(1998, 9, 21), date(2000, 1, 25)]
  wins: [3, 22, nil]
df.writeParquet(path)
echo readParquet(path, columns = ["rider", "born"], nRows = 2, rowIndexName = "nr")
```

```text
TBD
```

#### Scenario: Round trip
- **WHEN** a DataFrame with string, date and nullable integer columns is written and read back
- **THEN** the result equals the original, dtypes included

#### Scenario: Not Parquet
- **WHEN** bytes that are not Parquet are read
- **THEN** `PolarsError` is raised

### Requirement: Writing Parquet
`writeParquet(df, path, compression = ParquetCompression.Zstd, compressionLevel =
none(int), statistics = true, rowGroupSize = none(int))` SHALL write a Parquet file.
`compressionLevel` SHALL apply to `Gzip`, `Brotli` and `Zstd`; with another codec it
SHALL raise `ValueError`, and an out-of-range level SHALL raise `PolarsError`.

```nim
import std/sequtils
let path = getTempDir() / "sizes.parquet"
let df = newDataFrame(series("n", toSeq(1..1000)))
for c in [ParquetCompression.Uncompressed, ParquetCompression.Zstd]:
  df.writeParquet(path, compression = c)
  echo c, " ", getFileSize(path) < 5000
```

```text
TBD
```

#### Scenario: Every codec
- **WHEN** a DataFrame is written with each `ParquetCompression` value
- **THEN** each file reads back with the same rows

#### Scenario: Level without a level
- **WHEN** `writeParquet(path, compression = ParquetCompression.Snappy, compressionLevel = 3)` is called
- **THEN** `ValueError` is raised

#### Scenario: Missing directory
- **WHEN** the target directory does not exist
- **THEN** `IOError` is raised

### Requirement: Arrow IPC
The API SHALL provide `scanIpc` and `readIpc` with the read options of Parquet, and
`writeIpc(df, path, compression = IpcCompression.Uncompressed)` with `Lz4` and `Zstd`.

```nim
let path = getTempDir() / "riders.arrow"
let df = newDataFrame:
  rider: ["Seixas", "Pogačar"]
  start: [timeOfDay(13, 10), timeOfDay(13, 12)]
df.writeIpc(path, compression = IpcCompression.Lz4)
echo readIpc(path).schema
```

```text
TBD
```

#### Scenario: Round trip
- **WHEN** a DataFrame is written with each `IpcCompression` and read back
- **THEN** the result equals the original

### Requirement: Reading from streams
`readParquet` and `readIpc` SHALL also take a Nim `Stream` instead of a path, read all
of it when called, and take the same options.

```nim
import std/streams
let path = getTempDir() / "one.parquet"
newDataFrame(series("a", [1, 2])).writeParquet(path)
echo readParquet(newStringStream(readFile(path))).shape
```

```text
TBD
```

#### Scenario: Bytes in memory
- **WHEN** the bytes of a Parquet file are read with `readParquet(newStringStream(bytes))`
- **THEN** the result equals reading the file
