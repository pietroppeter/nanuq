# frame-utilities Specification

## Purpose
Smaller expression and frame functions: sampling, hashing, meta, comparing, stacking, updating and upsampling.

## Requirements

### Requirement: Smaller expression functions
Expressions SHALL have `shuffle(seed)`, `sample(n or fraction)`, `hash(seed)`, `get(i)`,
`argTrue`, `upperBound`, `lowerBound`, `extendConstant(value, n)`, `rle` (a struct of
`len` and `value`) and `reshape(dims)`, and `over(partitionBy, mappingStrategy)` with
`MappingStrategy.GroupToRows`, `Join` or `Explode`.

```nim
let df = newDataFrame:
  den: ["A", "A", "B"]
  kg: [410, 380, 500]
echo df.select(col("kg").get(1).alias("second"), col("kg").upperBound.alias("max"))
echo df.select((col("kg") > 400).argTrue.alias("heavy"))
echo df.select(col("den"), col("kg").over("den", MappingStrategy.Join).alias("all"))
echo df.select(col("den").rle).unnest("den")
```

```text
shape: (1, 2)
┌────────┬─────────────────────┐
│ second ┆ max                 │
│ ---    ┆ ---                 │
│ i64    ┆ i64                 │
╞════════╪═════════════════════╡
│ 380    ┆ 9223372036854775807 │
└────────┴─────────────────────┘
shape: (2, 1)
┌───────┐
│ heavy │
│ ---   │
│ u32   │
╞═══════╡
│ 0     │
│ 2     │
└───────┘
shape: (3, 2)
┌─────┬────────────┐
│ den ┆ all        │
│ --- ┆ ---        │
│ str ┆ list[i64]  │
╞═════╪════════════╡
│ A   ┆ [410, 380] │
│ A   ┆ [410, 380] │
│ B   ┆ [500]      │
└─────┴────────────┘
shape: (2, 2)
┌─────┬───────┐
│ len ┆ value │
│ --- ┆ ---   │
│ u32 ┆ str   │
╞═════╪═══════╡
│ 2   ┆ A     │
│ 1   ┆ B     │
└─────┴───────┘
```

#### Scenario: Seeded shuffle
- **WHEN** `shuffle(seed = 1)` is evaluated twice
- **THEN** both results are the same permutation

### Requirement: Names and meta
`name.toLowercase` and `name.toUppercase` SHALL change output names, and `e.meta` SHALL
give `outputName`, `rootNames`, `hasMultipleOutputs`, `isColumn`, `isLiteral` and
`undoAliases`.

```nim
let e = (col("kg") * 2).alias("double")
echo e.meta.outputName, " ", e.meta.rootNames, " ", col("*").meta.hasMultipleOutputs
let df = newDataFrame:
  Bear: ["Ada"]
echo df.select(col("Bear").name.toUppercase).columns
```

```text
double @["kg"] true
@["BEAR"]
```

#### Scenario: No output name
- **WHEN** `outputName` is asked of `col("*")`
- **THEN** `ComputeError` is raised

### Requirement: Comparing and stacking frames
`a.equals(b, nullEqual = true)` SHALL tell whether two frames (or Series) have the same
names, types and values; `vstack` and `extend` SHALL append the rows of a frame with the
same schema, and `hstack` SHALL add Series or the columns of another frame.

```nim
let a = newDataFrame:
  bear: ["Ada"]
  kg: [410]
let b = newDataFrame:
  bear: ["Bo"]
  kg: [380]
echo a.vstack(b).hstack([series("den", ["A", "B"])])
echo a.equals(a), " ", a.equals(b)
```

```text
shape: (2, 3)
┌──────┬─────┬─────┐
│ bear ┆ kg  ┆ den │
│ ---  ┆ --- ┆ --- │
│ str  ┆ i64 ┆ str │
╞══════╪═════╪═════╡
│ Ada  ┆ 410 ┆ A   │
│ Bo   ┆ 380 ┆ B   │
└──────┴─────┴─────┘
true false
```

#### Scenario: Nulls
- **WHEN** two frames with a null in the same place are compared with `nullEqual = false`
- **THEN** `equals` is false

### Requirement: Updating, upsampling and partitions
`df.update(other, on, how)` SHALL replace values of `df` with the non-null values of
`other` in matching rows; `df.upsample(timeColumn, every, groupBy)` SHALL insert rows for
missing times at a regular interval; `estimatedSize` SHALL give the frame's size;
`partitionBy(by, asDict = true)` SHALL give a table from key values to frames; and
`collectAll(lfs)` SHALL collect several LazyFrames.

```nim
let df = newDataFrame:
  bear: ["Ada", "Bo"]
  kg: [410, 380]
let fix = newDataFrame:
  bear: ["Bo"]
  kg: [395]
echo df.update(fix, on = "bear")
let t = newDataFrame:
  day: [date(2026, 3, 1), date(2026, 3, 4)]
  seen: [3, 1]
echo t.upsample("day", every = "1d")
echo df.partitionBy("bear", asDict = true).len, " ", collectAll([df.lazy, fix.lazy]).len
```

```text
shape: (2, 2)
┌──────┬─────┐
│ bear ┆ kg  │
│ ---  ┆ --- │
│ str  ┆ i64 │
╞══════╪═════╡
│ Bo   ┆ 395 │
│ Ada  ┆ 410 │
└──────┴─────┘
shape: (4, 2)
┌────────────┬──────┐
│ day        ┆ seen │
│ ---        ┆ ---  │
│ date       ┆ i64  │
╞════════════╪══════╡
│ 2026-03-01 ┆ 3    │
│ 2026-03-02 ┆ null │
│ 2026-03-03 ┆ null │
│ 2026-03-04 ┆ 1    │
└────────────┴──────┘
2 2
```

#### Scenario: Upsample by group
- **WHEN** `upsample` is called with `groupBy`
- **THEN** each group is filled between its own first and last time

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
shape: (2, 4)
┌─────┬─────┬─────┬───────┐
│ m   ┆ f   ┆ x   ┆ nx    │
│ --- ┆ --- ┆ --- ┆ ---   │
│ i64 ┆ i64 ┆ i64 ┆ bool  │
╞═════╪═════╪═════╪═══════╡
│ 12  ┆ 1   ┆ 3   ┆ false │
│ 6   ┆ 0   ┆ 6   ┆ true  │
└─────┴─────┴─────┴───────┘
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
shape: (2, 1)
┌───────────┐
│ r         │
│ ---       │
│ list[i64] │
╞═══════════╡
│ [1, 2]    │
│ [3, 4, 5] │
└───────────┘
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
shape: (1, 4)
┌─────┬─────┬──────┬──────┐
│ id  ┆ dur ┆ t_id ┆ time │
│ --- ┆ --- ┆ ---  ┆ ---  │
│ i64 ┆ i64 ┆ i64  ┆ i64  │
╞═════╪═════╪══════╪══════╡
│ 101 ┆ 100 ┆ 498  ┆ 130  │
└─────┴─────┴──────┴──────┘
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
shape: (2, 1)
┌─────┐
│ a   │
│ --- │
│ i64 │
╞═════╡
│ 1   │
│ 3   │
└─────┘
shape: (2, 3)
┌────────────┬────────────┬───────┐
│ breakpoint ┆ category   ┆ count │
│ ---        ┆ ---        ┆ ---   │
│ f64        ┆ cat        ┆ u32   │
╞════════════╪════════════╪═══════╡
│ 2.0        ┆ [0.0, 2.0] ┆ 2     │
│ 4.0        ┆ (2.0, 4.0] ┆ 2     │
└────────────┴────────────┴───────┘
shape: (3,)
Series: 'x' [i64]
[
	10
	2
	30
]
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
shape: (2, 3)
┌─────┬─────┬──────┐
│ x_0 ┆ x_1 ┆ x_2  │
│ --- ┆ --- ┆ ---  │
│ str ┆ str ┆ str  │
╞═════╪═════╪══════╡
│ a   ┆ c   ┆ e    │
│ b   ┆ d   ┆ null │
└─────┴─────┴──────┘
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
shape: (4, 1)
┌──────┐
│ x    │
│ ---  │
│ f64  │
╞══════╡
│ null │
│ 3.0  │
│ 5.0  │
│ 7.0  │
└──────┘
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
shape: (2, 2)
┌─────┬──────┐
│ a   ┆ type │
│ --- ┆ ---  │
│ i32 ┆ str  │
╞═════╪══════╡
│ 1   ┆ i32  │
│ 2   ┆ i32  │
└─────┴──────┘
```

#### Scenario: Unknown column
- **WHEN** `dtypeOf("nope")` is used
- **THEN** `ColumnNotFoundError` is raised when the query runs

### Requirement: Empty frames
`newDataFrame(schema = {...})` SHALL build a frame with those columns and types and no
rows (a `Schema` works too). `clear(n = 0)` on a DataFrame or LazyFrame SHALL keep the
columns and types with no rows, or `n` rows of nulls. `isEmpty` on a DataFrame or Series
SHALL be true when it has no rows.

```nim
let empty = newDataFrame(schema = {"bear": String, "kg": Int64})
echo empty
echo empty.isEmpty
echo newDataFrame(series("kg", @[410, 380])).clear(1)
```

```text
shape: (0, 2)
┌──────┬─────┐
│ bear ┆ kg  │
│ ---  ┆ --- │
│ str  ┆ i64 │
╞══════╪═════╡
└──────┴─────┘
true
shape: (1, 1)
┌──────┐
│ kg   │
│ ---  │
│ i64  │
╞══════╡
│ null │
└──────┘
```

#### Scenario: Same schema
- **WHEN** `df.clear` runs
- **THEN** its schema equals `df.schema` and its height is 0

### Requirement: Frame shortcuts
`getColumnIndex(name)` SHALL give a column's position (raising `ColumnNotFoundError`).
`rowsByKey(key, K, T, unique = false)` SHALL group the rows, as `T` objects or tuples, by
the values of `key` in order of appearance (with `unique`, the last row per key).
`shift(n, fillValue)` and `dropNans(subset)` SHALL work on frames as on each column;
LazyFrame `first` and `last` SHALL keep the first or last row. `rechunk` SHALL put each
column in one chunk, `shrinkToFit` SHALL drop spare capacity, and `nChunks` SHALL count
chunks.

```nim
import std/tables
let df = newDataFrame(series("station", @["A", "B", "A"]), series("rain", @[1.5, NaN, 3.0]))
echo df.getColumnIndex("rain")
echo df.rowsByKey("station", string, tuple[rain: float])
echo df.dropNans.shift(1)
```

```text
1
{"A": @[(rain: 1.5), (rain: 3.0)], "B": @[(rain: nan)]}
shape: (2, 2)
┌─────────┬──────┐
│ station ┆ rain │
│ ---     ┆ ---  │
│ str     ┆ f64  │
╞═════════╪══════╡
│ null    ┆ null │
│ A       ┆ 1.5  │
└─────────┴──────┘
```

#### Scenario: Unknown column
- **WHEN** `getColumnIndex("nope")` runs
- **THEN** `ColumnNotFoundError` is raised

### Requirement: Schema matching
`matchToSchema(schema, missingColumns, extraColumns, integerCast, floatCast)` SHALL put
the columns in the schema's order and types. A missing column SHALL raise unless
`missingColumns = Insert` (nulls), an extra column SHALL raise unless `extraColumns =
Ignore`, and integers and floats SHALL change type only with `CastPolicy.Upcast`.

```nim
let df = newDataFrame(series("b", @[1'i32]), series("a", @["x"]))
echo df.matchToSchema({"a": String, "b": Int64, "c": Float64},
                      missingColumns = MissingColumns.Insert, integerCast = CastPolicy.Upcast)
```

```text
shape: (1, 3)
┌─────┬─────┬──────┐
│ a   ┆ b   ┆ c    │
│ --- ┆ --- ┆ ---  │
│ str ┆ i64 ┆ f64  │
╞═════╪═════╪══════╡
│ x   ┆ 1   ┆ null │
└─────┴─────┴──────┘
```

#### Scenario: Missing column
- **WHEN** the schema has a column the frame lacks and `missingColumns` is `Raise`
- **THEN** `PolarsError` is raised

### Requirement: Merging sorted frames
`mergeSorted(other, key)` SHALL merge two frames sorted by `key` into one sorted frame.

```nim
let a = newDataFrame(series("k", @[1, 4]))
let b = newDataFrame(series("k", @[2, 3, 5]))
echo a.mergeSorted(b, "k").toList("k", int)
```

```text
@[1, 2, 3, 4, 5]
```

#### Scenario: Same columns
- **WHEN** both frames have the same columns, sorted by `key`
- **THEN** the result has all their rows, sorted

### Requirement: Query optimizations
`cache` SHALL mark part of a query to compute once. `QueryOptFlags` SHALL hold the
optimization switches (all on by default; `QueryOptFlags.none` turns off all but type
coercion and checks), applied with `withOptimizations` or `collect(optimizations,
engine)`.

```nim
let lf = newDataFrame(series("x", @[1, 2, 3])).lazy.filter(col("x") > 1)
echo lf.collect(QueryOptFlags.none).height
echo lf.cache.collect(QueryOptFlags(predicatePushdown: false)).height
```

```text
2
2
```

#### Scenario: Same rows
- **WHEN** a query is collected with every optimization on and with `QueryOptFlags.none`
- **THEN** the rows are the same
