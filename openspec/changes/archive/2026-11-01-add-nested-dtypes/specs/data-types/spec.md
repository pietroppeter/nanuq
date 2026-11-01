# Spec Delta

## MODIFIED Requirements

### Requirement: Nim types map to DataType
`dataType(T)` SHALL map `int8` to `int64`, `uint8` to `uint64`, `float32`, `float64`,
`bool` and `string` to their dtypes, `int` to `Int64` and `float` to `Float64`.
`dataType(T, timeUnit = Microseconds, timeZone = "")` SHALL map `Date`, `DateTime`,
std/times' `Duration` and `TimeOfDay` to Date, Datetime, Duration and Time. A Nim enum
SHALL map to an Enum of `$` of its values. `seq[T]` SHALL map to a List, `array[N, T]`
to an Array and objects and named tuples to a Struct of their fields, at any depth.
Other types SHALL not compile.

```nim
type Medal = enum Gold, Silver, Bronze
echo dataType(int), " ", dataType(float32), " ", dataType(uint8), " ", dataType(string)
echo dataType(Date), " ", dataType(DateTime), " ", dataType(Duration, Nanoseconds), " ", dataType(TimeOfDay)
echo dataType(Medal), " ", dataType(Medal).categories
echo dataType(seq[string]), " ", dataType(array[3, float]), " ", dataType(tuple[x: int, tags: seq[string]]).fields
```

```text
i64 f32 u8 str
date datetime[μs] duration[ns] time
enum @["Gold", "Silver", "Bronze"]
list[str] array[f64, 3] @[(name: "x", dtype: i64), (name: "tags", dtype: list[str])]
```

#### Scenario: Platform int
- **WHEN** `dataType(int)` is evaluated
- **THEN** it equals `Int64`, the dtype `series` builds from `seq[int]`

#### Scenario: Unsupported type
- **WHEN** `col("a").cast(ref int)` is compiled
- **THEN** compilation fails

#### Scenario: Unsupported unit
- **WHEN** `dataType(DateTime, Seconds)` is evaluated
- **THEN** `ValueError` is raised

#### Scenario: Nim enum
- **WHEN** `dataType(Medal)` is evaluated for `enum Gold, Silver, Bronze`
- **THEN** it equals `Enum(["Gold", "Silver", "Bronze"])`

#### Scenario: Nested Nim types
- **WHEN** `dataType(seq[seq[int]])` is evaluated
- **THEN** it equals `List(List(Int64))`
