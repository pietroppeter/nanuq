# Spec Delta

## MODIFIED Requirements

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
TBD
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
