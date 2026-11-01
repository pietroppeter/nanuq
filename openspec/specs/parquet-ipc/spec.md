# parquet-ipc Specification

## Purpose
Reading and writing Parquet and Arrow IPC (Feather v2) files, lazily or eagerly, from paths or Nim streams.

## Requirements

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
shape: (2, 3)
┌─────┬─────────┬────────────┐
│ nr  ┆ rider   ┆ born       │
│ --- ┆ ---     ┆ ---        │
│ u32 ┆ str     ┆ date       │
╞═════╪═════════╪════════════╡
│ 0   ┆ Seixas  ┆ 2006-09-24 │
│ 1   ┆ Pogačar ┆ 1998-09-21 │
└─────┴─────────┴────────────┘
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
Uncompressed false
Zstd true
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
{"rider": String, "start": TimeOfDay}
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
(2, 1)
```

#### Scenario: Bytes in memory
- **WHEN** the bytes of a Parquet file are read with `readParquet(newStringStream(bytes))`
- **THEN** the result equals reading the file

### Requirement: Hive partitioning switch
`scanParquet` and `readParquet` SHALL take `hivePartitioning`: `true` reads `key=value`
directories as columns, `false` does not, `none(bool)` (default) decides by the path.

```nim
let base = getTempDir() / "nanuq-hive"
let df = newDataFrame(series("year", @[2024, 2025]), series("n", @[1, 2]))
df.lazy.sinkParquet(PartitionBy(basePath: base, key: @["year"], includeKey: false), mkdir = true)
echo scanParquet(base / "**/*.parquet", hivePartitioning = false).collect.columns
```

```text
@["n"]
```

#### Scenario: On
- **WHEN** the same files are scanned with `hivePartitioning = true`
- **THEN** the frame has a `year` column

### Requirement: Arrow IPC streams
`writeIpcStream(path, compression)` SHALL write the Arrow IPC stream format, and
`readIpcStream` SHALL read it from a path or a stream.

```nim
let path = getTempDir() / "bears.arrows"
newDataFrame(series("kg", @[410, 380])).writeIpcStream(path)
echo readIpcStream(path).toList("kg", int)
```

```text
@[410, 380]
```

#### Scenario: Compressed
- **WHEN** a frame is written with `IpcCompression.Zstd` and read back
- **THEN** the frames are equal
