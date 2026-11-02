# Spec Delta

## MODIFIED Requirements

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
TBD
```

#### Scenario: Missing sheet
- **WHEN** `readExcel(path, sheetName = "nope")` is called
- **THEN** `IOError` is raised

#### Scenario: Round trip
- **WHEN** a frame of strings, integers, floats, booleans and dates is written and read back
- **THEN** the result equals the frame
