# Spec Delta

## MODIFIED Requirements

### Requirement: Scanning CSV
The API SHALL provide `scanCsv(path, ...)`, which returns a `LazyFrame` without reading the
file until the query runs. `path` SHALL accept a glob that matches several files with the
same columns. A glob whose files have different columns SHALL raise `PolarsError` when the
query runs.

```nim
let dir = getTempDir() / "census"
createDir dir
writeFile(dir / "week_01.csv", "station,bears\nNorth,3\nSouth,5\n")
writeFile(dir / "week_02.csv", "station,bears\nNorth,4\nSouth,2\nEast,1\n")
let weeks = scanCsv(dir / "*.csv")         # nothing is read yet
echo weeks.groupBy(col("station")).agg(col("bears").sum).sort("station").collect
```

```text
shape: (3, 2)
┌─────────┬───────┐
│ station ┆ bears │
│ ---     ┆ ---   │
│ str     ┆ i64   │
╞═════════╪═══════╡
│ East    ┆ 1     │
│ North   ┆ 7     │
│ South   ┆ 7     │
└─────────┴───────┘
```

#### Scenario: A folder of logs
- **WHEN** `scanCsv(dir / "*.csv").collect` runs on two files with the same columns and 2 and 3 rows
- **THEN** the result has 5 rows
