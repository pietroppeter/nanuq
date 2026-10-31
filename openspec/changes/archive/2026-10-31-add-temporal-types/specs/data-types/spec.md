# Spec Delta

## MODIFIED Requirements

### Requirement: DataType values
The API SHALL provide a `DataType` value with a `kind` of type `DataTypeKind` (a pure
enum, see `api-conventions`) covering
Boolean, Int8, Int16, Int32, Int64, UInt8, UInt16, UInt32, UInt64, Float32, Float64,
String, Null, Date, Datetime, Duration and Time, plus `DataTypeKind.Other` carrying
Polars' name for any other dtype. Datetime and Duration values SHALL carry a `timeUnit`
(std/times' `TimeUnit`: `Nanoseconds`, `Microseconds` or `Milliseconds`), and Datetime
values a `timeZone` ("" when naive). `dtype(df, col)` SHALL return a `DataType`.
`dtype == T` with a Nim type SHALL compare with `dataType(T)`, except that `DateTime`
and `Duration` SHALL match any time unit and zone.

```nim
let df = newDataFrame(series("a", [1, 2]))
echo df.dtype("a")                  # Polars' short name
echo df.dtype("a") == Int64
echo df.dtype("a").kind
let t = newDataFrame(series("at", [dateTime(2026, mJul, 4, zone = utc())],
                            timeUnit = Milliseconds, timeZone = "Europe/Rome"))
echo t.dtype("at"), " ", t.dtype("at").timeZone, " ", t.dtype("at") == DateTime
```

```text
i64
true
Int64
TBD
```

#### Scenario: Column dtype
- **WHEN** a DataFrame is built from a Nim `seq[int]` column `a`
- **THEN** `df.dtype("a") == Int64` and `$df.dtype("a") == "i64"`

#### Scenario: Unmodelled dtype
- **WHEN** a column has a dtype Nanuq does not model
- **THEN** its `kind` is `DataTypeKind.Other` and `$` returns Polars' name for it

#### Scenario: Zoned datetime
- **WHEN** a Datetime column has unit ms and zone Europe/Rome
- **THEN** `$` gives "datetime[ms, Europe/Rome]" and it equals `DateTime`

### Requirement: Casting
The API SHALL cast expressions (`e.cast(target, strict = true)`), all columns of a
DataFrame or LazyFrame (`cast(target, strict = true)`), where `target` is a Nim type or
a `DataType`, and named columns (`cast({"a": Int32}, strict = true)`) with `DataType`
values. Temporal Nim targets (`Date`, `DateTime`, `Duration`, `TimeOfDay`) SHALL take
`timeUnit = Microseconds` and, for `DateTime`, `timeZone = ""`. A strict cast SHALL
raise `PolarsError` (when the query runs) if a value cannot be converted; a non-strict
cast SHALL turn such values into nulls. Casting to a `DataTypeKind.Other` dtype SHALL
raise `PolarsError`.

```nim
let df = newDataFrame(series("a", [1, 2]), series("s", ["1", "x"]))
echo df.cast({"a": Int32}).dtype("a")
echo df.select(col("a").cast(float32)).dtype("a")
echo df.select(col("s").cast(Int64, strict = false))
echo df.select(col("a").cast(DateTime, timeUnit = Milliseconds, timeZone = "UTC")).dtype("a")
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
TBD
```

#### Scenario: Narrow an integer column
- **WHEN** `df.cast({"a": Int32})` runs on an i64 column
- **THEN** `dtype("a") == Int32` and `toList(df, "a", int)` returns the same values

#### Scenario: Nim type as target
- **WHEN** `col("a").cast(float32)` is selected from an i64 column
- **THEN** the result column has dtype `Float32`

#### Scenario: Strict failure
- **WHEN** a string column holding "1" and "x" is cast to `Int64` with `strict = true`
- **THEN** `PolarsError` is raised

#### Scenario: Non-strict cast
- **WHEN** the same column is cast with `strict = false`
- **THEN** the result is 1 and null

#### Scenario: Integers to dates
- **WHEN** a column of microseconds `[0, 86_400_000_000]` is cast to `DateTime` and then to `Date`
- **THEN** the result is 1970-01-01 and 1970-01-02

### Requirement: Nim types map to DataType
`dataType(T)` SHALL map `int8` to `int64`, `uint8` to `uint64`, `float32`, `float64`,
`bool` and `string` to their dtypes, `int` to `Int64` and `float` to `Float64`.
`dataType(T, timeUnit = Microseconds, timeZone = "")` SHALL map `Date`, `DateTime`,
std/times' `Duration` and `TimeOfDay` to Date, Datetime, Duration and Time. Other types
SHALL not compile.

```nim
echo dataType(int), " ", dataType(float32), " ", dataType(uint8), " ", dataType(string)
echo dataType(Date), " ", dataType(DateTime), " ", dataType(Duration, Nanoseconds), " ", dataType(TimeOfDay)
```

```text
i64 f32 u8 str
TBD
```

#### Scenario: Platform int
- **WHEN** `dataType(int)` is evaluated
- **THEN** it equals `Int64`, the dtype `series` builds from `seq[int]`

#### Scenario: Unsupported type
- **WHEN** `col("a").cast(seq[int])` is compiled
- **THEN** compilation fails

#### Scenario: Unsupported unit
- **WHEN** `dataType(DateTime, Seconds)` is evaluated
- **THEN** `ValueError` is raised
