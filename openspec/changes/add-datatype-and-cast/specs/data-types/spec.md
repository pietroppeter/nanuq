# Spec Delta

## ADDED Requirements

### Requirement: DataType values
The API SHALL provide a `DataType` value with a `kind` of type `DataTypeKind` covering
Boolean, Int8, Int16, Int32, Int64, UInt8, UInt16, UInt32, UInt64, Float32, Float64,
String and Null, plus `dkOther` carrying Polars' name for any other dtype. It SHALL
export constants with Polars' names (`Int64`, `String`, ...), `==`, and the predicates
`isInteger`, `isSignedInteger`, `isUnsignedInteger`, `isFloat` and `isNumeric`.
`dtype(df, col)` SHALL return a `DataType`.

#### Scenario: Column dtype
- **WHEN** a DataFrame is built from a Nim `seq[int]` column `a`
- **THEN** `df.dtype("a") == Int64`

#### Scenario: Predicates
- **WHEN** `isNumeric` is called on `UInt8`, `Float32` and `String`
- **THEN** it returns true, true and false

### Requirement: DataType names
`$` on a `DataType` SHALL return the Nim type name (`int64`, `uint8`, `float32`, `bool`,
`string`), `null` for Null, and Polars' name for `dkOther`. Polars' table output and
the HTML table header SHALL keep Polars' short names.

#### Scenario: Nim name
- **WHEN** `$df.dtype("a")` is evaluated on an i64 column
- **THEN** it returns `"int64"`

#### Scenario: Tables keep Polars names
- **WHEN** `toHtml` renders that DataFrame
- **THEN** the dtype row shows `i64`, as Polars does

#### Scenario: Unmodelled dtype
- **WHEN** a column has a dtype Nanuq does not model
- **THEN** its `kind` is `dkOther` and `$` returns Polars' name for it

### Requirement: Schemas
The API SHALL return the column names and dtypes of a DataFrame (`schema`) and of a
LazyFrame without collecting it (`collectSchema`) as a `Schema`, an
`OrderedTable[string, DataType]` in column order, and the dtypes alone with `dtypes`.

#### Scenario: Schema in column order
- **WHEN** `schema` is called on a DataFrame with columns `a` (i64) and `b` (str)
- **THEN** the keys are `a`, `b` in that order and the values are `Int64`, `String`

#### Scenario: Lazy schema
- **WHEN** `collectSchema` is called on a LazyFrame that adds `(col("a") * 1.5).alias("c")`
- **THEN** the schema has `c` with `Float64`, and the query is not executed

### Requirement: Casting
The API SHALL cast expressions (`e.cast(target, strict = true)`), all columns of a
DataFrame or LazyFrame (`cast(target, strict = true)`), where `target` is a Nim type or
a `DataType`, and named columns (`cast({"a": Int32}, strict = true)`) with `DataType`
values. A strict cast SHALL raise `NanuqError` (when the query
runs) if a value cannot be converted; a non-strict cast SHALL turn such values into
nulls. Casting to a `dkOther` dtype SHALL raise `NanuqError`.

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

### Requirement: Nim types map to DataType
`dataType(T)` SHALL map `int8` to `int64`, `uint8` to `uint64`, `float32`, `float64`,
`bool` and `string` to their dtypes, `int` to `Int64` and `float` to `Float64`. Other
types SHALL not compile.

#### Scenario: Platform int
- **WHEN** `dataType(int)` is evaluated
- **THEN** it equals `Int64`, the dtype `series` builds from `seq[int]`

#### Scenario: Unsupported type
- **WHEN** `col("a").cast(seq[int])` is compiled
- **THEN** compilation fails
