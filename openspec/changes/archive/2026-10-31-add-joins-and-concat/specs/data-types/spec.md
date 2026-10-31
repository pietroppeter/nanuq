# Spec Delta

## MODIFIED Requirements

### Requirement: DataType values
The API SHALL provide a `DataType` value with a `kind` of type `DataTypeKind` (a pure
enum, see `api-conventions`) covering
Boolean, Int8, Int16, Int32, Int64, UInt8, UInt16, UInt32, UInt64, Float32, Float64,
String and Null, plus `DataTypeKind.Other` carrying Polars' name for any other dtype. It SHALL
export constants with Polars' names (`Int64`, `String`, ...), `==`, `$` returning
Polars' short name, and the predicates `isInteger`, `isSignedInteger`,
`isUnsignedInteger`, `isFloat` and `isNumeric`. `dtype(df, col)` SHALL return a
`DataType`.

#### Scenario: Column dtype
- **WHEN** a DataFrame is built from a Nim `seq[int]` column `a`
- **THEN** `df.dtype("a") == Int64` and `$df.dtype("a") == "i64"`

#### Scenario: Unmodelled dtype
- **WHEN** a column has a dtype Nanuq does not model
- **THEN** its `kind` is `DataTypeKind.Other` and `$` returns Polars' name for it

#### Scenario: Predicates
- **WHEN** `isNumeric` is called on `UInt8`, `Float32` and `String`
- **THEN** it returns true, true and false

### Requirement: Casting
The API SHALL cast expressions (`e.cast(target, strict = true)`), all columns of a
DataFrame or LazyFrame (`cast(target, strict = true)`), where `target` is a Nim type or
a `DataType`, and named columns (`cast({"a": Int32}, strict = true)`) with `DataType`
values. A strict cast SHALL raise `NanuqError` (when the query
runs) if a value cannot be converted; a non-strict cast SHALL turn such values into
nulls. Casting to a `DataTypeKind.Other` dtype SHALL raise `NanuqError`.

#### Scenario: Narrow an integer column
- **WHEN** `df.cast({"a": Int32})` runs on an i64 column
- **THEN** `dtype("a") == Int32` and `toSeq(df, "a", int)` returns the same values

#### Scenario: Nim type as target
- **WHEN** `col("a").cast(float32)` is selected from an i64 column
- **THEN** the result column has dtype `Float32`

#### Scenario: Strict failure
- **WHEN** a string column holding "1" and "x" is cast to `Int64` with `strict = true`
- **THEN** `NanuqError` is raised

#### Scenario: Non-strict cast
- **WHEN** the same column is cast with `strict = false`
- **THEN** the result is 1 and null
