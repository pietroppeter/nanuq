# Spec Delta

## MODIFIED Requirements

### Requirement: DataType values
The API SHALL provide a `DataType` value with a `kind` of type `DataTypeKind` (a pure
enum, see `api-conventions`) covering
Boolean, Int8, Int16, Int32, Int64, UInt8, UInt16, UInt32, UInt64, Float32, Float64,
String, Null, Date, Datetime, Duration, Time, Categorical and Enum, plus
`DataTypeKind.Other` carrying Polars' name for any other dtype. Datetime and Duration
values SHALL carry a `timeUnit` (std/times' `TimeUnit`: `Nanoseconds`, `Microseconds`
or `Milliseconds`), Datetime values a `timeZone` ("" when naive), and Enum values their
`categories`. `dtype(df, col)` SHALL return a `DataType`. `dtype == T` with a Nim type
SHALL compare with `dataType(T)`, except that `DateTime` and `Duration` SHALL match any
time unit and zone.

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
datetime[ms, Europe/Rome] Europe/Rome true
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

#### Scenario: Enum categories
- **WHEN** a column is cast to `Enum(["low", "high"])`
- **THEN** `$` of its dtype gives "enum" and `categories` is `@["low", "high"]`

### Requirement: Nim types map to DataType
`dataType(T)` SHALL map `int8` to `int64`, `uint8` to `uint64`, `float32`, `float64`,
`bool` and `string` to their dtypes, `int` to `Int64` and `float` to `Float64`.
`dataType(T, timeUnit = Microseconds, timeZone = "")` SHALL map `Date`, `DateTime`,
std/times' `Duration` and `TimeOfDay` to Date, Datetime, Duration and Time. A Nim enum
SHALL map to an Enum of `$` of its values. Other types SHALL not compile.

```nim
type Medal = enum Gold, Silver, Bronze
echo dataType(int), " ", dataType(float32), " ", dataType(uint8), " ", dataType(string)
echo dataType(Date), " ", dataType(DateTime), " ", dataType(Duration, Nanoseconds), " ", dataType(TimeOfDay)
echo dataType(Medal), " ", dataType(Medal).categories
```

```text
i64 f32 u8 str
date datetime[μs] duration[ns] time
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

#### Scenario: Nim enum
- **WHEN** `dataType(Medal)` is evaluated for `enum Gold, Silver, Bronze`
- **THEN** it equals `Enum(["Gold", "Silver", "Bronze"])`
