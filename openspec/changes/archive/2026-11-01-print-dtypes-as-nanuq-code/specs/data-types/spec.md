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
time unit and zone. `$` SHALL print a data type as the Nanuq code that builds or names
it: the constant (`Int64`), the constructor (`Enum(["low", "high"])`), or for temporal
types the Nim type a column casts to (`Date`, `TimeOfDay`, `DateTime(Milliseconds,
"Europe/Rome")`, `Duration(Microseconds)`). Table headers, `glimpse` and `toHtml` SHALL
keep Polars' short names (`i64`).

```nim
let df = newDataFrame(series("a", [1, 2]))
echo df.dtype("a")                  # as Nanuq code
echo df.dtype("a") == Int64
echo df.dtype("a").kind
let t = newDataFrame(series("at", [dateTime(2026, mJul, 4, zone = utc())],
                            timeUnit = Milliseconds, timeZone = "Europe/Rome"))
echo t.dtype("at"), " ", t.dtype("at").timeZone, " ", t.dtype("at") == DateTime
```

```text
```

#### Scenario: Column dtype
- **WHEN** a DataFrame is built from a Nim `seq[int]` column `a`
- **THEN** `df.dtype("a") == Int64` and `$df.dtype("a") == "Int64"`

#### Scenario: Unmodelled dtype
- **WHEN** a column has a dtype Nanuq does not model
- **THEN** its `kind` is `DataTypeKind.Other` and `$` returns Polars' name for it

#### Scenario: Zoned datetime
- **WHEN** a Datetime column has unit ms and zone Europe/Rome
- **THEN** `$` gives `DateTime(Milliseconds, "Europe/Rome")` and it equals `DateTime`

#### Scenario: Enum categories
- **WHEN** a column is cast to `Enum(["low", "high"])`
- **THEN** `$` of its dtype gives `Enum(["low", "high"])` and `categories` is `@["low", "high"]`

#### Scenario: Tables keep short names
- **WHEN** a frame with an Int64 column is printed or turned into HTML
- **THEN** the column header shows `i64`

### Requirement: DataType constants and predicates
The API SHALL export `DataType` constants with Polars' names (`Int64`, `String`, ...),
`==`, `$` printing the constant's name, and the predicates `isInteger`,
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
