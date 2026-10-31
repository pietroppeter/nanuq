# data-types Specification

## Purpose
How Nanuq represents Polars data types in Nim (`DataType`), reads schemas, and casts
columns and expressions.

## Requirements

### Requirement: DataType values
The API SHALL provide a `DataType` value with a `kind` of type `DataTypeKind` (a pure
enum, see `api-conventions`) covering
Boolean, Int8, Int16, Int32, Int64, UInt8, UInt16, UInt32, UInt64, Float32, Float64,
String and Null, plus `DataTypeKind.Other` carrying Polars' name for any other dtype.
`dtype(df, col)` SHALL return a `DataType`.

```nim
let df = newDataFrame(series("a", [1, 2]))
echo df.dtype("a")                  # Polars' short name
echo df.dtype("a") == Int64
echo df.dtype("a").kind
```

```text
i64
true
Int64
```

#### Scenario: Column dtype
- **WHEN** a DataFrame is built from a Nim `seq[int]` column `a`
- **THEN** `df.dtype("a") == Int64` and `$df.dtype("a") == "i64"`

#### Scenario: Unmodelled dtype
- **WHEN** a column has a dtype Nanuq does not model
- **THEN** its `kind` is `DataTypeKind.Other` and `$` returns Polars' name for it

### Requirement: DataType constants and predicates
The API SHALL export `DataType` constants with Polars' names (`Int64`, `String`, ...),
`==`, `$` returning Polars' short name, and the predicates `isInteger`,
`isSignedInteger`, `isUnsignedInteger`, `isFloat` and `isNumeric`.

```nim
echo UInt8.isNumeric, " ", Float32.isFloat, " ", String.isNumeric
```

```text
true true false
```

#### Scenario: Predicates
- **WHEN** `isNumeric` is called on `UInt8`, `Float32` and `String`
- **THEN** it returns true, true and false

### Requirement: Schemas
The API SHALL return the column names and dtypes of a DataFrame (`schema`) and of a
LazyFrame without collecting it (`collectSchema`) as a `Schema`, an
`OrderedTable[string, DataType]` in column order, and the dtypes alone with `dtypes`.

```nim
let df = newDataFrame(series("a", [1, 2]), series("b", ["x", "y"]))
echo df.schema
echo df.lazy.withColumns((col("a") * 1.5).alias("c")).collectSchema   # nothing runs
```

```text
{"a": i64, "b": str}
{"a": i64, "b": str, "c": f64}
```

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
nulls. Casting to a `DataTypeKind.Other` dtype SHALL raise `NanuqError`.

```nim
let df = newDataFrame(series("a", [1, 2]), series("s", ["1", "x"]))
echo df.cast({"a": Int32}).dtype("a")
echo df.select(col("a").cast(float32)).dtype("a")
echo df.select(col("s").cast(Int64, strict = false))
```

```text
i32
f32
shape: (2, 1)
┌──────┐
│ s    │
│ ---  │
│ i64  │
╞══════╡
│ 1    │
│ null │
└──────┘
```

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

```nim
echo dataType(int), " ", dataType(float32), " ", dataType(uint8), " ", dataType(string)
```

```text
i64 f32 u8 str
```

#### Scenario: Platform int
- **WHEN** `dataType(int)` is evaluated
- **THEN** it equals `Int64`, the dtype `series` builds from `seq[int]`

#### Scenario: Unsupported type
- **WHEN** `col("a").cast(seq[int])` is compiled
- **THEN** compilation fails
