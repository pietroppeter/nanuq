# excel-io Specification

## Purpose
Reading and writing Excel workbooks with pure-Rust crates compiled into the Nanuq library (no Python, no system dependency).

## Requirements

### Requirement: Writing Excel
`writeExcel(df, path, worksheet = "Sheet1", includeHeader = true, autofit = false,
floatPrecision = none(int))` SHALL write the frame to one worksheet of a new .xlsx file:
a header row, then numbers, booleans, dates and datetimes as Excel values and other
values as text; nulls SHALL be empty cells.

```nim
let path = getTempDir() / "bears.xlsx"
let df = newDataFrame(series("bear", @["Ada", "Bo"]), series("kg", @[410.5, 380.0]),
                      series("seen", @[date(2024, 3, 1), date(2024, 3, 9)]))
df.writeExcel(path, worksheet = "census")
echo fileExists(path)
```

```text
true
```

#### Scenario: Missing directory
- **WHEN** the target directory does not exist
- **THEN** `IOError` is raised

### Requirement: Reading Excel
`readExcel(path, sheetName = "", sheetId = 1, hasHeader = true, headerRow = 0, skipRows = 0,
columns = [], schemaOverrides = [])` SHALL read one sheet (by name, else by position from 1)
of an .xlsx, .xlsm, .xlsb, .xls or .ods file. Row `headerRow` SHALL hold the column names,
and `skipRows` rows SHALL be skipped after it (from the top when `hasHeader = false`), as
Python's default engine (fastexcel) does. Column types SHALL be inferred from the cells:
Boolean, Int64 for whole numbers, Float64, Date for dates at midnight, Datetime[ms],
else String; `schemaOverrides` SHALL cast columns and `columns` keep only those.
`readExcelSheets(path)` SHALL read every sheet into a table by sheet name.

```nim
let path = getTempDir() / "bears.xlsx"
newDataFrame(series("bear", @["Ada", "Bo"]), series("kg", @[410, 380]),
             series("seen", @[date(2024, 3, 1), date(2024, 3, 9)])).writeExcel(path, worksheet = "census")
echo readExcel(path)
echo readExcel(path, sheetName = "census", skipRows = 1, hasHeader = false)
echo readExcel(path, skipRows = 1)
echo readExcelSheets(path).len
```

```text
shape: (2, 3)
┌──────┬─────┬────────────┐
│ bear ┆ kg  ┆ seen       │
│ ---  ┆ --- ┆ ---        │
│ str  ┆ i64 ┆ date       │
╞══════╪═════╪════════════╡
│ Ada  ┆ 410 ┆ 2024-03-01 │
│ Bo   ┆ 380 ┆ 2024-03-09 │
└──────┴─────┴────────────┘
shape: (2, 3)
┌──────────┬──────────┬────────────┐
│ column_1 ┆ column_2 ┆ column_3   │
│ ---      ┆ ---      ┆ ---        │
│ str      ┆ i64      ┆ date       │
╞══════════╪══════════╪════════════╡
│ Ada      ┆ 410      ┆ 2024-03-01 │
│ Bo       ┆ 380      ┆ 2024-03-09 │
└──────────┴──────────┴────────────┘
shape: (1, 3)
┌──────┬─────┬────────────┐
│ bear ┆ kg  ┆ seen       │
│ ---  ┆ --- ┆ ---        │
│ str  ┆ i64 ┆ date       │
╞══════╪═════╪════════════╡
│ Bo   ┆ 380 ┆ 2024-03-09 │
└──────┴─────┴────────────┘
1
```

#### Scenario: Missing sheet
- **WHEN** `readExcel(path, sheetName = "nope")` is called
- **THEN** `IOError` is raised

#### Scenario: Round trip
- **WHEN** a frame of strings, integers, floats, booleans and dates is written and read back
- **THEN** the result equals the frame
