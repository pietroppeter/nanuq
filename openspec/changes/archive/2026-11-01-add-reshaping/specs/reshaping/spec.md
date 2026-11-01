# Spec Delta

## ADDED Requirements

### Requirement: Pivot
`df.pivot(on, index, values, aggregateFunction = PivotAgg.Item, maintainOrder = true,
sortColumns = false, separator = "_")` SHALL turn each distinct value of the `on`
columns into a column (in order of appearance, or sorted), with one row per distinct
`index` value and cells from `values` combined by `aggregateFunction`, a `PivotAgg` or an
expression on `element()`. When `index` or `values` is left out it SHALL mean every other
column. `lf.pivot(on, onColumns, ...)` SHALL do the same lazily with the new columns
listed in the DataFrame `onColumns`.

```nim
let df = newDataFrame:
  year: [2023, 2023, 2024, 2024]
  season: ["DJF", "JJA", "DJF", "JJA"]
  oni: [-0.7, 1.1, 1.8, 0.0]
echo df.pivot("season", index = "year", values = "oni")
```

```text
TBD
```

#### Scenario: Aggregating duplicates
- **WHEN** two rows share an index and an `on` value and `aggregateFunction = Sum`
- **THEN** their cell holds the sum of both values

#### Scenario: Duplicates without an aggregation
- **WHEN** two rows share an index and an `on` value and no aggregation is given
- **THEN** `pivot` raises a `PolarsError`

### Requirement: Unpivot
`unpivot(on, index, variableName = "variable", valueName = "value")` on a DataFrame or
LazyFrame SHALL turn the `on` columns (by default every column not in `index`) into rows,
one per `index` value and `on` column, holding the column's name and value.

```nim
let df = newDataFrame:
  year: [2023, 2024]
  DJF: [-0.7, 1.8]
  JJA: [1.1, 0.0]
echo df.unpivot(index = "year", variableName = "season", valueName = "oni")
```

```text
TBD
```

#### Scenario: Round trip
- **WHEN** a long frame is pivoted and the result unpivoted on the new columns
- **THEN** the rows are the original rows

### Requirement: Transpose
`df.transpose(includeHeader = false, headerName = "column", columnNames)` SHALL turn rows
into columns, naming them `columnNames` or column_0, column_1, ..., and with
`includeHeader` SHALL put the old column names in a first column `headerName`.

```nim
let df = newDataFrame:
  lima: [22.1, 24.3]
  quito: [14.0, 14.2]
echo df.transpose(includeHeader = true, headerName = "station", columnNames = ["jan", "feb"])
```

```text
TBD
```

#### Scenario: Default names
- **WHEN** a frame with two rows is transposed without names
- **THEN** its columns are column_0 and column_1

### Requirement: Partition
`df.partitionBy(by, maintainOrder = true, includeKey = true)` SHALL return one DataFrame
per distinct value of the `by` columns, in order of appearance with `maintainOrder`, and
without the `by` columns when `includeKey` is false.

```nim
let df = newDataFrame:
  phase: ["El Niño", "La Niña", "El Niño"]
  year: [2015, 2020, 2023]
for part in df.partitionBy("phase", includeKey = false):
  echo part.toList("year", int)
```

```text
TBD
```

#### Scenario: Several keys
- **WHEN** `partitionBy(["a", "b"])` runs on rows with three distinct (a, b) pairs
- **THEN** the result has three frames

### Requirement: Dummy columns
`df.toDummies(columns, separator = "_", dropFirst = false, dropNulls = false)` SHALL
replace each listed column (all by default) by one 0/1 column per distinct value, named
column, separator and value.

```nim
let df = newDataFrame:
  phase: ["warm", "cold", "warm"]
echo df.toDummies()
```

```text
TBD
```

#### Scenario: Drop first
- **WHEN** `toDummies(dropFirst = true)` runs on a column with values a and b
- **THEN** only one dummy column remains
