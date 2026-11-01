# Spec Delta

## ADDED Requirements

### Requirement: Ordering values
`e.sort(descending, nullsLast)` SHALL sort the values of `e`, `e.argSort` SHALL return
the row indices that sort them, `e.sortBy(by, descending)` SHALL order `e` by one or
more other columns, and `e.reverse` SHALL reverse it, so that these work inside `agg`
and `over`.

```nim
let df = newDataFrame:
  basin: ["Pacific", "Pacific", "Atlantic", "Atlantic"]
  storm: ["Ana", "Bud", "Cleo", "Dan"]
  wind: [120, 185, 150, 95]
echo df.groupBy(col.basin).agg(col.storm.sortBy(col.wind, descending = true).first
                               .alias("strongest")).sort("basin").collect
```

```text
TBD
```

#### Scenario: Sorted column
- **WHEN** `col.x.sort(descending = true)` is selected on 2, 3, 1
- **THEN** the result is 3, 2, 1

### Requirement: Picking values
`e.head(n = 10)`, `e.tail(n = 10)`, `e.slice(offset, length)`, `e.gather(indices)`,
`e.gatherEvery(n, offset = 0)`, `e.topK(k = 5)`, `e.bottomK(k = 5)`,
`e.topKBy(by, k = 5, reverse)` and `e.bottomKBy(...)` SHALL return those values of `e`;
`e.indexOf(value)` SHALL return the index of the first occurrence of `value` (or null),
and `e.searchSorted(element, side)` the index at which `element` would be inserted to
keep `e` sorted.

```nim
let df = newDataFrame:
  year: [1982, 1997, 2015, 2023]
  oni: [2.2, 2.4, 2.6, 2.0]
echo df.select(col.year.topKBy(col.oni, k = 2).alias("top2"),
               col.oni.topK(2).alias("peak"))
```

```text
TBD
```

#### Scenario: Gather by position
- **WHEN** `col.x.gather([0, 2])` is selected on 10, 20, 30
- **THEN** the result is 10, 30

#### Scenario: Insertion point
- **WHEN** `searchSorted(2)` runs on 1, 2, 2, 3 with side `Left` and `Right`
- **THEN** the results are 1 and 3

### Requirement: Distinct values
`e.unique(maintainOrder = false)` SHALL return the distinct values,
`isUnique`, `isDuplicated`, `isFirstDistinct` and `isLastDistinct` SHALL flag rows by
how their value repeats, `argUnique` SHALL return the index of each value's first
occurrence, `uniqueCounts` the number of occurrences of each distinct value in order of
appearance, and `approxNUnique` an estimate of the number of distinct values.

```nim
let df = newDataFrame:
  station: ["Lima", "Quito", "Lima", "Paita"]
echo df.withColumns(col.station.isDuplicated.alias("dup"),
                    col.station.isFirstDistinct.alias("first"))
```

```text
TBD
```

#### Scenario: Unique in order
- **WHEN** `unique(maintainOrder = true)` runs on b, a, b, c
- **THEN** the result is b, a, c

### Requirement: Recoding values
`e.replace(old, new)` and `e.replace({old: new, ...})` SHALL replace each listed value
and keep the others and the data type; `e.replaceStrict(...)` SHALL require every value
to be listed, unless a `default` is given, and SHALL take the data type of the new values.

```nim
let df = newDataFrame:
  phase: ["N", "EN", "LN", "EN"]
echo df.withColumns(col.phase.replaceStrict({"EN": "El Niño", "LN": "La Niña"},
                                            default = "neutral").alias("name"))
```

```text
TBD
```

#### Scenario: Value not listed
- **WHEN** `replaceStrict({"a": 1})` runs on a column holding "a" and "b"
- **THEN** collecting raises `InvalidOperationError`

#### Scenario: Unequal lists
- **WHEN** `replace([1, 2], [10])` is built
- **THEN** `ValueError` is raised

### Requirement: Binning
`e.cut(breaks, labels, leftClosed = false)` SHALL put each value in the interval between
breaks it falls into, as a Categorical labelled like "(-0.5, 0.5]" or with `labels` (one
more than breaks), and `e.qcut(quantiles, ...)` SHALL do the same at the quantiles of the
values, given as probabilities or as a number of equal groups.

```nim
let df = newDataFrame:
  oni: [-1.6, -0.2, 0.3, 0.9, 2.4]
echo df.withColumns(col.oni.cut([-0.5, 0.5], labels = ["La Niña", "neutral", "El Niño"])
                    .alias("phase"))
```

```text
TBD
```

#### Scenario: Default labels
- **WHEN** `cut([0.0])` runs on -1.0 and 1.0
- **THEN** the labels are "(-inf, 0]" and "(0, inf]"

### Requirement: Value counts
`valueCounts(column, sort = false, normalize = false, name)` on a DataFrame or LazyFrame
SHALL return each distinct value of `column` with its number of occurrences in a column
`count` (or its share in `proportion` with `normalize`, or the column `name`), most
frequent first with `sort`.

```nim
let df = newDataFrame:
  phase: ["neutral", "El Niño", "neutral", "La Niña", "neutral", "El Niño"]
echo df.valueCounts("phase", sort = true)
```

```text
TBD
```

#### Scenario: Proportions
- **WHEN** `valueCounts("x", normalize = true)` runs on a, a, b, b
- **THEN** each value has proportion 0.5
