# streaming Specification

## Purpose
Running lazy queries on Polars' streaming engine and writing results straight to files (sinks), whole or partitioned by key, without holding them in memory.

## Requirements

### Requirement: Choosing the engine
`collect(lf, engine)` SHALL run the query with the given `Engine`: `Auto` (Polars picks,
today the in-memory engine), `InMemory` or `Streaming`, which processes the data in
batches. Every engine SHALL give the same rows; `collectAll(lfs, engine)` SHALL take the
same choice.

```nim
let lf = newDataFrame(series("kg", @[410, 380, 455])).lazy
echo lf.filter(col("kg") > 400).collect(engine = Engine.Streaming)
```

```text
shape: (2, 1)
┌─────┐
│ kg  │
│ --- │
│ i64 │
╞═════╡
│ 410 │
│ 455 │
└─────┘
```

#### Scenario: Same result
- **WHEN** a group-by query is collected with `Engine.InMemory` and with `Engine.Streaming`
- **THEN** both frames are equal after sorting

### Requirement: Sinks
`sinkParquet`, `sinkIpc`, `sinkCsv` and `sinkNdjson` SHALL run a LazyFrame with the
streaming engine and write the result to a file, with the options of `writeParquet`,
`writeIpc`, `writeCsv` and `writeNdjson`, plus `maintainOrder = true` and `mkdir = false`
(create missing directories). With `lazy = true` they SHALL return the sink as a
LazyFrame, which writes the file when collected; `collectAll` SHALL run several such
sinks together.

```nim
let dir = getTempDir() / "nanuq-sinks"
let lf = newDataFrame(series("bear", @["Ada", "Bo"]), series("kg", @[410, 380])).lazy
lf.sinkCsv(dir / "bears.csv", mkdir = true)
echo readFile(dir / "bears.csv")
let sinks = [lf.sinkParquet(dir / "bears.parquet", lazy = true),
             lf.filter(col("kg") > 400).sinkNdjson(dir / "big.ndjson", lazy = true)]
discard collectAll(sinks)
echo readParquet(dir / "bears.parquet").height, " ", readFile(dir / "big.ndjson")
```

```text
bear,kg
Ada,410
Bo,380

2 {"bear":"Ada","kg":410}
```

#### Scenario: Missing directory
- **WHEN** a sink targets a directory that does not exist and `mkdir` is false
- **THEN** `IOError` is raised and no file is written

### Requirement: Partitioned sinks
A sink SHALL accept a `PartitionBy(basePath, key, includeKey = true, maxRowsPerFile)`
target instead of a path: with `key` it SHALL write one Hive-style directory per key
value (`basePath/key=value/...`), without it files of at most `maxRowsPerFile` rows.

```nim
let base = getTempDir() / "nanuq-by-year"
let df = newDataFrame(series("year", @[2024, 2024, 2025]), series("n", @[1, 2, 3]))
df.lazy.sinkParquet(PartitionBy(basePath: base, key: @["year"]), mkdir = true)
echo scanParquet(base / "**/*.parquet").sort("n").collect
```

```text
shape: (3, 2)
┌──────┬─────┐
│ year ┆ n   │
│ ---  ┆ --- │
│ i64  ┆ i64 │
╞══════╪═════╡
│ 2024 ┆ 1   │
│ 2024 ┆ 2   │
│ 2025 ┆ 3   │
└──────┴─────┘
```

#### Scenario: Rows per file
- **WHEN** 10 rows are sunk with `PartitionBy(basePath: dir, maxRowsPerFile: 4)`
- **THEN** reading every file in `dir` gives the 10 rows back

### Requirement: Profiling
`profile(lf)` SHALL run the query and return a tuple of the result and a frame with one
row per executed node (`node`, `start`, `end`, in microseconds).

```nim
let (res, timings) = newDataFrame(series("x", @[1, 2, 3])).lazy.select(col("x").sum).profile
echo res
echo timings.columns
```

```text
shape: (1, 1)
┌─────┐
│ x   │
│ --- │
│ i64 │
╞═════╡
│ 6   │
└─────┘
@["node", "start", "end"]
```

#### Scenario: Timings
- **WHEN** a query is profiled
- **THEN** every `end` is at least its `start`
