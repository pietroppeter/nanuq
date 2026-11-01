# frame-verbs Specification

## Purpose
Column and row verbs on DataFrames and LazyFrames: dropping and renaming columns, row
windows, unique rows, row indexes, sorting by several keys, and sampling.

## Requirements

### Requirement: Dropping and renaming columns
LazyFrame and DataFrame SHALL support `drop(columns, strict = true)`, with one column
name or a list of names, and `rename(mapping: openArray[(string, string)], strict = true)`. With `strict = true`, a
column that does not exist SHALL raise `PolarsError`. With `strict = false`, it SHALL be
ignored.

```nim
let df = newDataFrame(series("a", [1]), series("b", [2]), series("c", [3]))
echo df.drop("b").columns                  # one name
echo df.drop(["a", "b"]).columns           # several
echo df.drop("zzz", strict = false).columns
echo df.rename({"a": "x"}).columns
```

```text
@["a", "c"]
@["c"]
@["a", "b", "c"]
@["x", "b", "c"]
```

#### Scenario: Drop
- **WHEN** `df.drop("b")` runs on columns `a`, `b`, `c`
- **THEN** the columns are `a`, `c`, and `df.drop(["a", "b"])` leaves `c`

#### Scenario: Rename
- **WHEN** `df.rename({"a": "x"})` runs on columns `a`, `b`
- **THEN** the columns are `x`, `b`

#### Scenario: Strict
- **WHEN** `df.drop("zzz")` runs
- **THEN** `PolarsError` is raised, and `df.drop("zzz", strict = false)` returns the frame unchanged

### Requirement: Row windows
LazyFrame and DataFrame SHALL support `head(n = 5)`, `tail(n = 5)`, `slice(offset)` and
`slice(offset, length)`. A negative offset SHALL count from the end. `reverse()` SHALL
reverse the row order.

```nim
let df = newDataFrame(series("n", [1, 2, 3, 4, 5]))
echo df.tail(2).toList("n", int)
echo df.slice(-3, 2).toList("n", int)       # negative offset counts from the end
echo df.slice(1).toList("n", int)           # to the end
echo df.reverse.toList("n", int)
```

```text
@[4, 5]
@[3, 4]
@[2, 3, 4, 5]
@[5, 4, 3, 2, 1]
```

#### Scenario: Tail
- **WHEN** `tail(2)` runs on rows 1 to 5
- **THEN** the result is rows 4 and 5

#### Scenario: Slice from the end
- **WHEN** `slice(-3, 2)` runs on rows 1 to 5
- **THEN** the result is rows 3 and 4

#### Scenario: Slice to the end
- **WHEN** `slice(1)` runs on rows 1 to 5
- **THEN** the result is rows 2 to 5

### Requirement: Unique rows
LazyFrame and DataFrame SHALL support `unique(subset = [], keep, maintainOrder = false)`,
with one column name or a list of names, judging duplicates on all columns when the
subset is empty. `keep` is a pure
enum `UniqueKeepStrategy` (`Any` (default), `First`, `Last`, `None`). With
`maintainOrder = true`, the rows SHALL keep their original order.

```nim
let df = newDataFrame(series("k", ["a", "b", "a"]), series("v", [1, 2, 3]))
echo df.unique("k", keep = First, maintainOrder = true)
echo df.unique("k", keep = None)
```

```text
shape: (2, 2)
┌─────┬─────┐
│ k   ┆ v   │
│ --- ┆ --- │
│ str ┆ i64 │
╞═════╪═════╡
│ a   ┆ 1   │
│ b   ┆ 2   │
└─────┴─────┘
shape: (1, 2)
┌─────┬─────┐
│ k   ┆ v   │
│ --- ┆ --- │
│ str ┆ i64 │
╞═════╪═════╡
│ b   ┆ 2   │
└─────┴─────┘
```

#### Scenario: Keep first
- **WHEN** `unique("k", keep = First, maintainOrder = true)` runs on keys a, b, a with values 1, 2, 3
- **THEN** the result is (a, 1), (b, 2)

#### Scenario: Keep none
- **WHEN** the same frame is made unique on `k` with `keep = None`
- **THEN** only (b, 2) remains

### Requirement: Row index
LazyFrame and DataFrame SHALL support `withRowIndex(name = "index", offset = 0)`, which
adds an unsigned integer column with that name as the first column, counting from
`offset`.

```nim
let df = newDataFrame(series("bear", ["Nanuq", "Ursa", "Kuma"]))
echo df.withRowIndex("n", offset = 1)
```

```text
shape: (3, 2)
┌─────┬───────┐
│ n   ┆ bear  │
│ --- ┆ ---   │
│ u32 ┆ str   │
╞═════╪═══════╡
│ 1   ┆ Nanuq │
│ 2   ┆ Ursa  │
│ 3   ┆ Kuma  │
└─────┴───────┘
```

#### Scenario: Offset
- **WHEN** `withRowIndex("n", offset = 1)` runs on three rows
- **THEN** the first column is `n` with values 1, 2, 3

### Requirement: Sorting by several keys
LazyFrame and DataFrame SHALL sort by several column names or expressions with
`sort(by, descending: openArray[bool] = [], nullsLast: openArray[bool] = [],
maintainOrder = false)`. An empty list SHALL mean false for every key, and one value
SHALL apply to every key. Another length SHALL raise `PolarsError`. The one-column
`sort(by: string, descending = false, nullsLast = false, maintainOrder = false)` SHALL
remain.

```nim
let df = newDataFrame(series("g", ["b", "a", "b", "a"]), series("v", [1, 2, 3, 4]))
echo df.sort(["g", "v"], descending = [false, true])
```

```text
shape: (4, 2)
┌─────┬─────┐
│ g   ┆ v   │
│ --- ┆ --- │
│ str ┆ i64 │
╞═════╪═════╡
│ a   ┆ 4   │
│ a   ┆ 2   │
│ b   ┆ 3   │
│ b   ┆ 1   │
└─────┴─────┘
```

#### Scenario: Two keys
- **WHEN** a frame is sorted by `["g", "v"]` with `descending = [false, true]`
- **THEN** rows are ordered by `g` ascending and, within each `g`, by `v` descending

#### Scenario: Nulls last
- **WHEN** a column holding null, 2, 1 is sorted with `nullsLast = true`
- **THEN** the order is 1, 2, null

#### Scenario: Length mismatch
- **WHEN** a sort by three keys gets `descending = [true, false]`
- **THEN** `PolarsError` is raised

### Requirement: Sampling rows
DataFrame SHALL support `sample(n, withReplacement = false, shuffle = none(bool), seed =
none(int))` and `sample(fraction, ...)` with the same options. `shuffle` SHALL also accept
a plain `bool`: `true` shuffles the rows, `false` keeps their order and `none` gives no
order guarantee, as in Polars. Asking for more rows than
there are without replacement SHALL raise `PolarsError`. The same seed SHALL give the same
rows. `seed` SHALL also accept a plain `int` (`seed = 42`), and `setRandomSeed(seed)` SHALL
seed Polars' global generator, used when no seed is passed.

```nim
let df = newDataFrame(series("n", [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]))
echo df.sample(3, seed = 42) == df.sample(3, seed = 42)   # same seed, same rows
echo df.sample(fraction = 0.5).shape
setRandomSeed(42)
let a = df.sample(4)
setRandomSeed(42)
echo a == df.sample(4)
```

```text
false
(5, 1)
false
```

#### Scenario: Seeded sample
- **WHEN** `sample(3, seed = some(42))` runs twice on the same 10-row frame
- **THEN** both results have 3 rows and are equal

#### Scenario: Global seed
- **WHEN** `setRandomSeed(42)` is called before each of two `sample(4)` calls on the same frame
- **THEN** both results are equal

#### Scenario: Fraction
- **WHEN** `sample(fraction = 0.5)` runs on 10 rows
- **THEN** the result has 5 rows

#### Scenario: Too many rows
- **WHEN** `sample(11)` runs on 10 rows
- **THEN** `PolarsError` is raised

### Requirement: Every n-th row
LazyFrame and DataFrame SHALL support `gatherEvery(n, offset = 0)`, keeping rows
`offset`, `offset + n`, `offset + 2n`, ... (Python's `gather_every`).

```nim
let df = newDataFrame:
  month: [1, 2, 3, 4, 5, 6]
echo df.gatherEvery(3, offset = 2)
```

```text
shape: (2, 1)
┌───────┐
│ month │
│ ---   │
│ i64   │
╞═══════╡
│ 3     │
│ 6     │
└───────┘
```

#### Scenario: Offset past the end
- **WHEN** `gatherEvery(2, offset = 10)` runs on 6 rows
- **THEN** the result has no rows

### Requirement: Frame interpolation
DataFrame and LazyFrame SHALL support `interpolate(how = InterpolationMethod.Linear)`,
filling the nulls of every column as `Expr.interpolate` does (Python's
`DataFrame.interpolate`).

```nim
let df = newDataFrame:
  day: [1, 2, 3]
  temp: [some(-2.0), none(float), some(1.0)]
echo df.interpolate
```

```text
shape: (3, 2)
┌─────┬──────┐
│ day ┆ temp │
│ --- ┆ ---  │
│ f64 ┆ f64  │
╞═════╪══════╡
│ 1.0 ┆ -2.0 │
│ 2.0 ┆ -0.5 │
│ 3.0 ┆ 1.0  │
└─────┴──────┘
```

#### Scenario: Integer column
- **WHEN** an integer column with a null between 1 and 5 is interpolated
- **THEN** it becomes a float column holding 1.0, 3.0, 5.0

### Requirement: Casting by data type
DataFrame and LazyFrame `cast` SHALL also take a mapping from data types, or from
selectors, to data types: `cast({Float64: Float32})` casts every Float64 column,
`cast({col(SomeNumber): Float32})` every column the selector picks; other columns are
kept.

```nim
let df = newDataFrame:
  kg: [410.5, 380.0]
  cubs: [1, 0]
  bear: ["Ada", "Bo"]
echo df.cast({Float64: Float32}).schema
echo df.cast({col(SomeNumber): Float32}).schema
```

```text
{"kg": Float32, "cubs": Int64, "bear": String}
{"kg": Float32, "cubs": Float32, "bear": String}
```

#### Scenario: Other columns kept
- **WHEN** `cast({Float64: Float32})` runs on a frame with an Int64 column
- **THEN** the Int64 column is unchanged

### Requirement: Several filter predicates
DataFrame and LazyFrame `filter` SHALL take several predicates, `filter(a, b, ...)`,
keeping the rows where all of them hold (Python's `filter(a, b)`).

```nim
let df = newDataFrame:
  peak: ["Mont Blanc", "Monte Rosa", "Gran Paradiso"]
  m: [4806, 4634, 4061]
  italy: [true, true, true]
echo df.filter(col.m > 4500, col.italy)
```

```text
shape: (2, 3)
┌────────────┬──────┬───────┐
│ peak       ┆ m    ┆ italy │
│ ---        ┆ ---  ┆ ---   │
│ str        ┆ i64  ┆ bool  │
╞════════════╪══════╪═══════╡
│ Mont Blanc ┆ 4806 ┆ true  │
│ Monte Rosa ┆ 4634 ┆ true  │
└────────────┴──────┴───────┘
```

#### Scenario: All must hold
- **WHEN** a row meets one predicate but not the other
- **THEN** it is dropped

### Requirement: Group order parameter
`groupBy` on DataFrame and LazyFrame SHALL accept `maintainOrder` (Python's
`maintain_order`), with names or expressions; the groups SHALL keep the order their keys
first appear whatever its value.

```nim
let df = newDataFrame:
  country: ["CH", "IT", "CH"]
  m: [4634, 4061, 4506]
echo df.groupBy("country", maintainOrder = true).agg(col.m.max)
```

```text
shape: (2, 2)
┌─────────┬──────┐
│ country ┆ m    │
│ ---     ┆ ---  │
│ str     ┆ i64  │
╞═════════╪══════╡
│ CH      ┆ 4634 │
│ IT      ┆ 4061 │
└─────────┴──────┘
```

#### Scenario: Order kept
- **WHEN** keys appear as CH, IT, CH and `maintainOrder = false` is passed
- **THEN** the groups come out as CH, IT

### Requirement: Frame aggregations
DataFrames and LazyFrames SHALL provide `sum`, `mean`, `median`, `product`, `min`, `max`,
`std(ddof = 1)`, `var(ddof = 1)`, `quantile(q, interpolation)`, `nUnique`, `count` and
`nullCount()`, each giving one row with the aggregation of every column; columns of a
type the aggregation does not apply to (strings for `sum`) SHALL give null.

```nim
let df = newDataFrame(series("bear", @["Ada", "Bo", "Cy"]), series("kg", @[410, 380, 455]))
echo df.sum
echo df.max
echo df.nullCount
```

```text
shape: (1, 2)
┌──────┬──────┐
│ bear ┆ kg   │
│ ---  ┆ ---  │
│ str  ┆ i64  │
╞══════╪══════╡
│ null ┆ 1245 │
└──────┴──────┘
shape: (1, 2)
┌──────┬─────┐
│ bear ┆ kg  │
│ ---  ┆ --- │
│ str  ┆ i64 │
╞══════╪═════╡
│ Cy   ┆ 455 │
└──────┴─────┘
shape: (1, 2)
┌──────┬─────┐
│ bear ┆ kg  │
│ ---  ┆ --- │
│ u32  ┆ u32 │
╞══════╪═════╡
│ 0    ┆ 0   │
└──────┴─────┘
```

#### Scenario: Lazy
- **WHEN** `df.lazy.mean.collect` runs
- **THEN** it equals `df.mean`

### Requirement: Group-by shortcuts
GroupBy and LazyGroupBy SHALL provide `len(name = "len")`, `count`, `head(n = 5)`,
`tail(n = 5)`, `first`, `last`, `sum`, `mean`, `median`, `min`, `max`, `nUnique`,
`quantile(q)` and `all`, each aggregating every non-key column per group, with groups in
order of appearance.

```nim
let df = newDataFrame(series("den", @["N", "S", "N"]), series("kg", @[410, 380, 455]))
echo df.groupBy("den").max
echo df.groupBy("den").len
echo df.groupBy("den").head(1)
```

```text
shape: (2, 2)
┌─────┬─────┐
│ den ┆ kg  │
│ --- ┆ --- │
│ str ┆ i64 │
╞═════╪═════╡
│ N   ┆ 455 │
│ S   ┆ 380 │
└─────┴─────┘
shape: (2, 2)
┌─────┬─────┐
│ den ┆ len │
│ --- ┆ --- │
│ str ┆ u32 │
╞═════╪═════╡
│ N   ┆ 2   │
│ S   ┆ 1   │
└─────┴─────┘
shape: (2, 2)
┌─────┬─────┐
│ den ┆ kg  │
│ --- ┆ --- │
│ str ┆ i64 │
╞═════╪═════╡
│ N   ┆ 410 │
│ S   ┆ 380 │
└─────┴─────┘
```

#### Scenario: Not a plain group-by
- **WHEN** `head` is called on a `groupByDynamic`
- **THEN** `InvalidOperationError` is raised

### Requirement: Iterating over groups
`for key, part in df.groupBy(columns)` SHALL yield each group's key values (as strings,
in `by` order) and its rows, groups in order of appearance.

```nim
let df = newDataFrame(series("den", @["N", "S", "N"]), series("kg", @[410, 380, 455]))
for key, part in df.groupBy("den"):
  echo key, " ", part.height
```

```text
@["N"] 2
@["S"] 1
```

#### Scenario: Several keys
- **WHEN** a frame is grouped by two columns and iterated
- **THEN** each key holds two values

### Requirement: Frame fillNan and select without a frame
`fillNan(value)` on DataFrames and LazyFrames SHALL replace NaN in float columns
(`nil` for null), and `select(exprs...)` SHALL evaluate expressions without a frame.

```nim
echo newDataFrame(series("x", @[1.0, NaN])).fillNan(0.0)
echo select(lit(1).alias("one"), intRange(0, 3).alias("i"))
```

```text
shape: (2, 1)
┌─────┐
│ x   │
│ --- │
│ f64 │
╞═════╡
│ 1.0 │
│ 0.0 │
└─────┘
shape: (3, 2)
┌─────┬─────┐
│ one ┆ i   │
│ --- ┆ --- │
│ i32 ┆ i64 │
╞═════╪═════╡
│ 1   ┆ 0   │
│ 1   ┆ 1   │
│ 1   ┆ 2   │
└─────┴─────┘
```

#### Scenario: Other columns
- **WHEN** a frame with an integer and a float column gets `fillNan(0.0)`
- **THEN** the integer column is unchanged
