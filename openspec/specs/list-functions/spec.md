# list-functions Specification

## Purpose
Functions on list columns: the `list` namespace, explode, implode and concatList.

## Requirements

### Requirement: List aggregations and access
`e.list` SHALL give a namespace whose methods work on each list of a List (or Array)
column: `len`, `sum`, `min`, `max`, `mean`, `median`, `std`, `var`, `first`, `last`,
`argMin`, `argMax`, `nUnique`, `any`, `all` give one value per list; `get(i)` (negative
from the end), `gather`, `gatherEvery`, `slice`, `head`, `tail` pick values;
`contains(x)`, `countMatches(x)` and `join(separator)` compare or join them.

```nim
let df = newDataFrame:
  cubs: [@[2, 1, 3], @[], @[4]]
  names: [@["Ada", "Bo"], @["Cy"], @[]]
echo df.select(col("cubs").list.len.alias("n"), col("cubs").list.sum.alias("sum"),
               col("cubs").list.get(0, nullOnOob = true).alias("first"),
               col("cubs").list.contains(3).alias("has3"),
               col("names").list.join(", ").alias("names"))
```

```text
shape: (3, 5)
┌─────┬─────┬───────┬───────┬─────────┐
│ n   ┆ sum ┆ first ┆ has3  ┆ names   │
│ --- ┆ --- ┆ ---   ┆ ---   ┆ ---     │
│ u32 ┆ i64 ┆ i64   ┆ bool  ┆ str     │
╞═════╪═════╪═══════╪═══════╪═════════╡
│ 3   ┆ 6   ┆ 2     ┆ true  ┆ Ada, Bo │
│ 0   ┆ 0   ┆ null  ┆ false ┆ Cy      │
│ 1   ┆ 4   ┆ 4     ┆ false ┆         │
└─────┴─────┴───────┴───────┴─────────┘
```

#### Scenario: Index out of bounds
- **WHEN** `list.get(5)` is evaluated on a list of 3 values without `nullOnOob`
- **THEN** `ComputeError` is raised; with `nullOnOob = true` the value is null

### Requirement: List transforms
`e.list` SHALL have `sort`, `reverse`, `unique`, `dropNulls`, `diff`, `shift`, `sample`,
`filter(predicate)`, the set operations `union`, `setDifference`, `setIntersection` and
`setSymmetricDifference` with another list expression, `toArray(width)` and
`toStruct(fields)`, each giving a list (array or struct) per row.

```nim
let df = newDataFrame:
  a: [@[3, 1, 3], @[2]]
  b: [@[1, 5], @[2, 4]]
echo df.select(col("a").list.sort.alias("sorted"), col("a").list.unique(maintainOrder = true).alias("unique"),
               col("a").list.union(col("b")).alias("union"),
               col("a").list.filter(element() > 1).alias("gt1"))
```

```text
shape: (2, 4)
┌───────────┬───────────┬───────────┬───────────┐
│ sorted    ┆ unique    ┆ union     ┆ gt1       │
│ ---       ┆ ---       ┆ ---       ┆ ---       │
│ list[i64] ┆ list[i64] ┆ list[i64] ┆ list[i64] │
╞═══════════╪═══════════╪═══════════╪═══════════╡
│ [1, 3, 3] ┆ [3, 1]    ┆ [3, 1, 5] ┆ [3, 3]    │
│ [2]       ┆ [2]       ┆ [2, 4]    ┆ [2]       │
└───────────┴───────────┴───────────┴───────────┘
```

#### Scenario: Lists to structs
- **WHEN** `list.toStruct(["x", "y"])` is evaluated on lists of two values
- **THEN** the result is a struct column with fields `x` and `y`

### Requirement: Expressions on list elements
`list.eval(e)` SHALL evaluate `e` on the values of each list, with `element()` standing
for them, and give a list per row; `list.agg(e)` SHALL do the same for an aggregation and
give one value per row.

```nim
let df = newDataFrame:
  weights: [@[410.0, 380.0], @[450.0, 470.0, 455.0]]
echo df.select(col("weights").list.eval(element().rank).alias("rank"),
               col("weights").list.agg(element().max - element().min).alias("spread"))
```

```text
shape: (2, 2)
┌─────────────────┬────────┐
│ rank            ┆ spread │
│ ---             ┆ ---    │
│ list[f64]       ┆ f64    │
╞═════════════════╪════════╡
│ [2.0, 1.0]      ┆ 30.0   │
│ [1.0, 3.0, 2.0] ┆ 20.0   │
└─────────────────┴────────┘
```

#### Scenario: Element outside a list
- **WHEN** `element()` is used in a `select` that is not inside `list.eval`
- **THEN** evaluating it raises a Polars error

### Requirement: Explode and implode
`e.explode` and `e.list.explode` SHALL give one row per list value, `df.explode(columns)`
SHALL do the same for whole rows (eager and lazy; `emptyAsNull` and `keepNulls` default
to true, as in Polars), `e.implode` SHALL collect a column into one list, and
`concatList(exprs)` SHALL join values and lists of several columns into one list per row.

```nim
let df = newDataFrame:
  den: ["A", "B", "C"]
  cubs: [@["Ada", "Bo"], @[], @["Cy"]]
echo df.explode("cubs")
echo df.select(concatList(col("den"), col("cubs")).alias("all"))
echo df.select(col("den").implode)
```

```text
shape: (4, 2)
┌─────┬──────┐
│ den ┆ cubs │
│ --- ┆ ---  │
│ str ┆ str  │
╞═════╪══════╡
│ A   ┆ Ada  │
│ A   ┆ Bo   │
│ B   ┆ null │
│ C   ┆ Cy   │
└─────┴──────┘
shape: (3, 1)
┌────────────────────┐
│ all                │
│ ---                │
│ list[str]          │
╞════════════════════╡
│ ["A", "Ada", "Bo"] │
│ ["B"]              │
│ ["C", "Cy"]        │
└────────────────────┘
shape: (1, 1)
┌─────────────────┐
│ den             │
│ ---             │
│ list[str]       │
╞═════════════════╡
│ ["A", "B", "C"] │
└─────────────────┘
```

#### Scenario: Empty lists
- **WHEN** a frame with an empty list is exploded with `emptyAsNull = false`
- **THEN** that row is dropped instead of giving a null

### Requirement: Exploding several columns by name
DataFrame and LazyFrame `explode` SHALL also take several column names as separate
arguments: `explode("a", "b")` is `explode(["a", "b"])`.

```nim
let df = newDataFrame:
  peak: ["Mont Blanc", "Monte Rosa"]
  huts: [@["Goûter", "Cosmiques"], @["Margherita", "Gnifetti"]]
  m: [@[3835, 3613], @[4554, 3647]]
echo df.explode("huts", "m")
```

```text
shape: (4, 3)
┌────────────┬────────────┬──────┐
│ peak       ┆ huts       ┆ m    │
│ ---        ┆ ---        ┆ ---  │
│ str        ┆ str        ┆ i64  │
╞════════════╪════════════╪══════╡
│ Mont Blanc ┆ Goûter     ┆ 3835 │
│ Mont Blanc ┆ Cosmiques  ┆ 3613 │
│ Monte Rosa ┆ Margherita ┆ 4554 │
│ Monte Rosa ┆ Gnifetti   ┆ 3647 │
└────────────┴────────────┴──────┘
```

#### Scenario: Lists of equal length
- **WHEN** two list columns with lists of the same lengths are exploded together
- **THEN** each row holds the matching elements of both
