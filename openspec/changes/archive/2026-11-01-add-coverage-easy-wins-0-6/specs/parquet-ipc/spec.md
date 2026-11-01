# Spec Delta

## ADDED Requirements

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
TBD
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
TBD
```

#### Scenario: Compressed
- **WHEN** a frame is written with `IpcCompression.Zstd` and read back
- **THEN** the frames are equal
