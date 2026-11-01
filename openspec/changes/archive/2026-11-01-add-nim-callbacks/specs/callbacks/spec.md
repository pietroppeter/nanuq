# Spec Delta

## ADDED Requirements

### Requirement: Typed element callbacks
`e.mapElements(f)` SHALL call the Nim proc or closure `f: proc (x: T): U` on each value of
`e`, read as `T` (as `toList` reads it: objects and named tuples for structs, seqs for
lists), and give a column of `dataType(U)`. Nulls SHALL stay null without a call unless
`T` is an `Option`. An exception in `f` SHALL raise `ComputeError` with its message when
the query runs.

```nim
type Bear = object
  name: string
  kg: int
let df = newDataFrame:
  name: ["Ada", "Bo", "Cy"]
  kg: [410, nil, 500]
let tag = proc (b: Bear): string = b.name & " (" & $b.kg & " kg)"
echo df.select(col("kg").mapElements(proc (x: int): float = x / 1000).alias("t"),
               asStruct(col("name"), col("kg").fillNull(0)).mapElements(tag).alias("tag"))
```

```text
TBD
```

#### Scenario: Error in the callback
- **WHEN** the callback raises `ValueError("no bears")`
- **THEN** collecting raises `ComputeError` whose message holds "no bears"

### Requirement: Batch callbacks
`e.mapBatches(f)` SHALL call `f: proc (s: Series): Series` with the whole column, or in a
group-by with each group's values; the result SHALL keep the input type unless
`returnDtype` is given, and with `returnsScalar` a group-by SHALL get one value per group
instead of a list.

```nim
let df = newDataFrame:
  cubs: [1, 0, 1]
  kg: [410, 380, 500]
echo df.select(col("kg").mapBatches(proc (s: Series): Series = s * 2))
echo df.groupBy("cubs").agg(col("kg").mapBatches(proc (s: Series): Series = s.max,
                                                  returnsScalar = true)).sort("cubs")
```

```text
TBD
```

#### Scenario: Other result type
- **WHEN** `mapBatches(proc (s: Series): Series = s / 10, Float64)` runs on an integer column
- **THEN** the result is a `f64` column

### Requirement: Folds
`fold(acc, f, exprs)` SHALL combine columns left to right with `f: proc (acc, x: Series):
Series`, starting from `acc`; `reduce(f, exprs)` SHALL start from the first column, and
`cumFold` and `cumReduce` SHALL keep each step as a struct field.

```nim
let df = newDataFrame:
  a: [1, 2]
  b: [10, 20]
  c: [100, 200]
echo df.select(fold(lit(0), proc (acc, x: Series): Series = acc + x, col("*")).alias("sum"))
```

```text
TBD
```

#### Scenario: Reduce
- **WHEN** `reduce` with `+` runs on columns a and b
- **THEN** the result is 11 and 22

### Requirement: Name and group callbacks
`name.map(f)` SHALL rename outputs with `f: proc (name: string): string`, and
`groupBy(...).mapGroups(f)` SHALL call `f: proc (df: DataFrame): DataFrame` on each
group, in order of first occurrence, and concatenate the results.

```nim
let df = newDataFrame:
  den: ["A", "B", "A"]
  kg: [410, 380, 500]
echo df.select(col("*").name.map(proc (n: string): string = n.toUpperAscii))
echo df.groupBy("den").mapGroups(proc (g: DataFrame): DataFrame = g.sort("kg", descending = true).head(1))
```

```text
TBD
```

#### Scenario: Empty frame
- **WHEN** `mapGroups` runs on an empty frame
- **THEN** the result is an empty frame with the same columns
