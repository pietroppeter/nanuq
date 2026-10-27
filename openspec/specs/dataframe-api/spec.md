# dataframe-api Specification

## Purpose
The Nim-facing API in `src/nanuq.nim`: DataFrame, LazyFrame and Expr values backed by
Polars, with automatic memory management and Nim exceptions.

## Requirements

### Requirement: Automatic memory management
`DataFrame`, `LazyFrame`, `Expr` and `Series` SHALL be Nim `ref` types whose destructors
free the underlying Rust object when the last reference goes away. Copying the inner
objects SHALL be a compile-time error.

#### Scenario: Shared value
- **WHEN** two Nim variables refer to the same DataFrame
- **THEN** the Rust object is freed once, after both go out of scope

### Requirement: Errors as NanuqError
Any failing FFI call SHALL raise `NanuqError` carrying the message from Rust.

#### Scenario: Bad column
- **WHEN** a query selects a column that does not exist
- **THEN** `NanuqError` is raised with the Polars error message

### Requirement: Building and reading data
The API SHALL build a DataFrame from Nim arrays of int, float, bool and string
(`series`, `newDataFrame`), read and write CSV with a header row, and expose `shape`,
`columns`, `dtype`, `head`, `$` (Polars' table format), single cells and whole columns.

#### Scenario: Columns of different lengths
- **WHEN** `newDataFrame` gets series of different lengths
- **THEN** `NanuqError` is raised

### Requirement: Reading columns by type
Reading as `float` SHALL accept any integer or float column; as `string`, any column,
formatted as Polars does; as `int`, only integer columns; as `bool`, only boolean
columns. A dtype that does not match SHALL raise `NanuqError`.

#### Scenario: Integers read as floats
- **WHEN** an i64 column holding 1, 2 is read with `toSeq(df, "a", float)`
- **THEN** the result is `@[1.0, 2.0]`

#### Scenario: Floats are not truncated to int
- **WHEN** an f64 column is read with `toSeq(df, "a", int)`
- **THEN** `NanuqError` is raised

#### Scenario: Bool column
- **WHEN** a bool column is read with `toSeq(df, "d", bool)`
- **THEN** the result holds the column's values

### Requirement: Expressions and lazy queries
The API SHALL provide `col`, `lit`, arithmetic, comparison and boolean operators on `Expr`
(lifting Nim literals automatically), the aggregations sum, mean, min, max, count, first,
last, nUnique and std, and `alias`. LazyFrame SHALL support select, withColumns, filter,
groupBy/agg, sort, limit, explain and collect. DataFrame SHALL offer eager shortcuts for
select, withColumns, filter and sort.

#### Scenario: Lazy group by
- **WHEN** a LazyFrame is filtered, grouped, aggregated and sorted
- **THEN** nothing runs until `collect`, which returns the resulting DataFrame
