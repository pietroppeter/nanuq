# Spec Delta

## ADDED Requirements

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
TBD
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
TBD
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
TBD
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
TBD
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
TBD
```

#### Scenario: Same rows
- **WHEN** a query is collected with every optimization on and with `QueryOptFlags.none`
- **THEN** the rows are the same
