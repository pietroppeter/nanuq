# csv-io Specification

## Purpose
Reading and writing CSV files: lazy scans of a file or a glob, eager reads, and the named read and write options, following Polars' names and defaults.

## Requirements

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

### Requirement: CSV read options
`readCsv` and `scanCsv` SHALL take these named options with Polars' defaults:
- `separator = ','` and `hasHeader = true`
- `nullValues` and `schemaOverrides` (`(string, DataType)` pairs)
- `skipRows = 0`, `nRows = none(int)` and `columns` (all when empty)
- `inferSchemaLength = some(100)`, where `none` scans all rows
- `ignoreErrors = false` and `decimalComma = false`
- `tryParseDates = false`, which reads ISO dates, datetimes and times as temporal columns

`nRows` and `inferSchemaLength` SHALL also accept a plain `int`.

```nim
let path = getTempDir() / "survey.csv"
writeFile(path, "Polar survey 2026\nexported by hand\nstation;bears;weight\n" &
                "North;3;410\nSouth;lots;380\nEast;1;355\n")
echo readCsv(path, separator = ';', skipRows = 2, nRows = 2, nullValues = ["lots"],
             schemaOverrides = {"weight": Float64}, columns = ["station", "weight", "bears"])
let stages = getTempDir() / "stages.csv"
writeFile(stages, "stage,day,start\n1,2026-07-04,13:10:00\n2,2026-07-05,12:45:00\n")
echo readCsv(stages, tryParseDates = true).schema
```

```text
shape: (2, 3)
┌─────────┬────────┬───────┐
│ station ┆ weight ┆ bears │
│ ---     ┆ ---    ┆ ---   │
│ str     ┆ f64    ┆ i64   │
╞═════════╪════════╪═══════╡
│ North   ┆ 410.0  ┆ 3     │
│ South   ┆ 380.0  ┆ null  │
└─────────┴────────┴───────┘
{"stage": i64, "day": date, "start": time}
```

#### Scenario: Semicolons and null words
- **WHEN** a file with `;` separators and the value "lots" is read with `separator = ';', nullValues = ["lots"]`
- **THEN** the columns are split at `;` and "lots" is null

#### Scenario: Override a dtype
- **WHEN** a column of whole numbers is read with `schemaOverrides = {"n": Float64}`
- **THEN** `dtype("n") == Float64`

#### Scenario: Preamble and limit
- **WHEN** a file with two preamble lines and 10 data rows is read with `skipRows = 2, nRows = 3`
- **THEN** the header is the third line and the result has 3 rows

#### Scenario: Columns
- **WHEN** a file with columns `a`, `b` and `c` is read with `columns = ["c", "a"]`
- **THEN** the result has columns `c` and `a`

#### Scenario: Dates
- **WHEN** a column of ISO dates is read with and without `tryParseDates = true`
- **THEN** its dtype is `Date` and `String`

### Requirement: CSV write options
`writeCsv(df, path, ...)` SHALL take these named options:
- `separator = ','` and `includeHeader = true`
- `nullValue = ""`
- `quoteStyle = Necessary`, a pure enum `QuoteStyle` (`Necessary`, `Always`,
  `NonNumeric`, `Never`)
- `floatPrecision = none(int)` (also a plain `int`)
- `decimalComma = false`

```nim
let df = newDataFrame(series("bear", ["Nanuq", "Ursa"]),
                      series("weight", [some(410.256), none(float)]))
let path = getTempDir() / "out.csv"
df.writeCsv(path, separator = ';', nullValue = "NA", floatPrecision = 1,
            decimalComma = true, quoteStyle = NonNumeric)
echo readFile(path)
```

```text
"bear";"weight"
"Nanuq";410,3
"Ursa";NA
```

#### Scenario: Spreadsheet in a comma-decimal locale
- **WHEN** a frame with 1.5 is written with `separator = ';', decimalComma = true` and read back with the same options
- **THEN** the file holds `1,5` and the value read back is 1.5

#### Scenario: Quote everything
- **WHEN** a frame is written with `quoteStyle = Always`
- **THEN** every field in the file is quoted

#### Scenario: Null marker and precision
- **WHEN** a frame with a null and 3.14159 is written with `nullValue = "NA", floatPrecision = 2`
- **THEN** the file holds `NA` and `3.14`

### Requirement: Reading CSV from a stream
`readCsv` SHALL also take a Nim `Stream` instead of a path, read all of it when called,
and take every CSV read option.

```nim
import std/streams
let text = "station;bears\nNorth;3\nSouth;NA\n"
echo readCsv(newStringStream(text), separator = ';', nullValues = ["NA"])
```

```text
shape: (2, 2)
┌─────────┬───────┐
│ station ┆ bears │
│ ---     ┆ ---   │
│ str     ┆ i64   │
╞═════════╪═══════╡
│ North   ┆ 3     │
│ South   ┆ null  │
└─────────┴───────┘
```

#### Scenario: Same options
- **WHEN** CSV text with `;` separators and "NA" is read from a stream with `separator = ';', nullValues = ["NA"]`
- **THEN** the result equals reading the same text from a file with those options

#### Scenario: Empty stream
- **WHEN** an empty stream is read
- **THEN** `NoDataError` is raised
