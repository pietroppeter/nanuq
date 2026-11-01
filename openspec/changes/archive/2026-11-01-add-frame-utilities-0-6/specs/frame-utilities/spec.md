# Spec Delta

## ADDED Requirements

### Requirement: Operator methods and xor
Expressions SHALL have the method spellings `add`, `sub`, `mul`, `truediv`, `floordiv`,
`eq`, `ne`, `lt`, `le`, `gt`, `ge` (with an expression, number, string or bool) and
`neg`, giving the same result as the operators, and `xor` SHALL be logical on booleans
and bitwise on integers.

```nim
let df = newDataFrame(series("a", @[6, 3]), series("ok", @[true, false]))
echo df.select(col("a").mul(2).alias("m"), col("a").floordiv(4).alias("f"),
               (col("a") xor 5).alias("x"), (col("ok") xor true).alias("nx"))
```

```text
TBD
```

#### Scenario: Same as operators
- **WHEN** `col("a").sub(1)` and `col("a") - 1` are selected
- **THEN** both columns are equal

### Requirement: Ranges per row
`intRanges(start, stop, step = 1, dtype = Int64)`, `dateRanges(start, stop, interval)`
and `datetimeRanges(start, stop, interval, closed, timeUnit, timeZone)` SHALL give one
list per row, with columns or values as bounds; `arange` SHALL be `intRange`.

```nim
let df = newDataFrame(series("lo", @[1, 3]), series("hi", @[3, 6]))
echo df.select(intRanges(col("lo"), col("hi")).alias("r"))
```

```text
TBD
```

#### Scenario: Dates
- **WHEN** `dateRanges` runs from 2024-01-01 to 2024-01-03
- **THEN** the list holds 3 dates

### Requirement: Inequality joins
`joinWhere(other, predicates..., suffix = "_right")` on DataFrames and LazyFrames SHALL
join the rows of both frames for which every predicate holds; clashing columns of
`other` SHALL get `suffix`.

```nim
let east = newDataFrame(series("id", @[100, 101]), series("dur", @[140, 100]))
let west = newDataFrame(series("t_id", @[404, 498]), series("time", @[90, 130]))
echo east.joinWhere(west, col("dur") < col("time"))
```

```text
TBD
```

#### Scenario: No match
- **WHEN** no pair of rows satisfies the predicates
- **THEN** the result has no rows

### Requirement: Frame and Series helpers
The API SHALL provide `append` (rows of another frame, in place), `remove(predicate)`
(rows where it is not true), `setSorted`, `Series.isSorted(descending, nullsLast)`,
`explainAll(lfs)`, `threadPoolSize()`, `readParquetSchema(path)`, `fromEpoch(column,
unit)`, `hist(bins, binCount, includeCategory, includeBreakpoint)` on Expr and Series,
`Series.scatter(indices, values)` and `` `set`(mask, value) ``.

```nim
var df = newDataFrame(series("a", @[1, 2]))
df.append(newDataFrame(series("a", @[3])))
echo df.remove(col("a") == 2)
echo series("x", @[1.0, 2.0, 2.5, 4.0]).hist(bins = [0.0, 2.0, 4.0])
echo series("x", @[1, 2, 3]).scatter([0, 2], [10, 30])
```

```text
TBD
```

#### Scenario: Remove keeps nulls
- **WHEN** `remove(col("a") > 1)` runs on a column with a null
- **THEN** the null row stays

### Requirement: Unstack
`unstack(step, how = UnstackDirection.Vertical, columns = [], fillValues = nil)` SHALL
reshape each column into columns `<name>_<i>` of `step` values each (`Vertical`) or with
`step` values per row (`Horizontal`), padding the end with nulls or `fillValues`.

```nim
let df = newDataFrame(series("x", @["a", "b", "c", "d", "e"]))
echo df.unstack(2)
```

```text
TBD
```

#### Scenario: Horizontal
- **WHEN** 5 values are unstacked horizontally with step 2 and fill 0
- **THEN** column `_0` holds values 1, 3, 5 and column `_1` holds 2, 4, 0

### Requirement: Rolling Nim functions
`rollingMap(f, windowSize, minPeriods = windowSize, center = false)` SHALL apply a typed
Nim proc to each window's non-null values, giving null when a window has fewer than
`minPeriods` values.

```nim
import std/sequtils
let df = newDataFrame(series("x", @[1.0, 2.0, 3.0, 4.0]))
echo df.select(col("x").rollingMap(proc (w: seq[float]): float = w.foldl(a + b), windowSize = 2))
```

```text
TBD
```

#### Scenario: Centered
- **WHEN** `center = true` with window 3
- **THEN** each value's window is the value and its two neighbours

### Requirement: Data type of an expression
`dtypeOf(expr or column)` SHALL stand for the type of an expression at run time:
`cast(e, dtypeOf(...))` casts to it, `display` gives its short name as a string value,
`innerDtype` the inner type of a List or Array.

```nim
let df = newDataFrame(series("a", @[1.5, 2.5]), series("b", @[1'i32, 2'i32]))
echo df.select(col("a").cast(dtypeOf("b"), strict = false), dtypeOf("b").display.alias("type"))
```

```text
TBD
```

#### Scenario: Unknown column
- **WHEN** `dtypeOf("nope")` is used
- **THEN** `ColumnNotFoundError` is raised when the query runs
