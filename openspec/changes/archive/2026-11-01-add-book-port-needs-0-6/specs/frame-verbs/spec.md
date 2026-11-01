# Spec Delta

## ADDED Requirements

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
TBD
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
TBD
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
TBD
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
TBD
```

#### Scenario: Other columns
- **WHEN** a frame with an integer and a float column gets `fillNan(0.0)`
- **THEN** the integer column is unchanged
