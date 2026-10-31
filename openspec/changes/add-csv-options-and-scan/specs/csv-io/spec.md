# Spec Delta

## ADDED Requirements

### Requirement: Scanning CSV
The API SHALL provide `scanCsv(path, ...)`, which returns a `LazyFrame` without reading the
file until the query runs. `path` SHALL accept a glob that matches several files with the
same columns. A glob whose files have different columns SHALL raise `NanuqError` when the
query runs.

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

`nRows` and `inferSchemaLength` SHALL also accept a plain `int`.

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

### Requirement: CSV write options
`writeCsv(df, path, ...)` SHALL take these named options:
- `separator = ','` and `includeHeader = true`
- `nullValue = ""`
- `quoteStyle = Necessary`, a pure enum `QuoteStyle` (`Necessary`, `Always`,
  `NonNumeric`, `Never`)
- `floatPrecision = none(int)` (also a plain `int`)
- `decimalComma = false`

#### Scenario: Spreadsheet in a comma-decimal locale
- **WHEN** a frame with 1.5 is written with `separator = ';', decimalComma = true` and read back with the same options
- **THEN** the file holds `1,5` and the value read back is 1.5

#### Scenario: Quote everything
- **WHEN** a frame is written with `quoteStyle = Always`
- **THEN** every field in the file is quoted

#### Scenario: Null marker and precision
- **WHEN** a frame with a null and 3.14159 is written with `nullValue = "NA", floatPrecision = 2`
- **THEN** the file holds `NA` and `3.14`
