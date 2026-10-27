# Spec Delta

## MODIFIED Requirements

### Requirement: Building and reading data
The API SHALL build a DataFrame from Nim arrays of int, float, bool and string
(`series`, `newDataFrame`), read and write CSV with a header row, and expose `shape`,
`columns`, `dtype`, `head`, `$` (Polars' table format), single cells and whole columns.
Reading as `float` SHALL accept any integer or float column; reading as `string` SHALL
accept any column, formatting values as Polars does; reading as `int` SHALL accept only
integer columns; reading as `bool` SHALL accept only boolean columns. A dtype that does
not match SHALL raise `NanuqError`.

#### Scenario: Columns of different lengths
- **WHEN** `newDataFrame` gets series of different lengths
- **THEN** `NanuqError` is raised

#### Scenario: Integers read as floats
- **WHEN** an i64 column holding 1, 2 is read with `toSeq(df, "a", float)`
- **THEN** the result is `@[1.0, 2.0]`

#### Scenario: Floats are not truncated to int
- **WHEN** an f64 column is read with `toSeq(df, "a", int)`
- **THEN** `NanuqError` is raised

#### Scenario: Bool column
- **WHEN** a bool column is read with `toSeq(df, "d", bool)`
- **THEN** the result holds the column's values
