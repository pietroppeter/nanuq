# column-selectors Specification

## Purpose
Selecting several columns at once, by Nim type, by name, by regex or all of them, minus
excluded names, and renaming the outputs of such expressions.

## Requirements

### Requirement: Selecting by Nim type
`col` SHALL accept Nim types and typeclasses and return a `Selector`.
- `SomeNumber`, `SomeInteger`, `SomeSignedInt`, `SomeUnsignedInt` and `SomeFloat` SHALL
  select the matching Polars dtype category.
- A concrete type SHALL select the dtype `dataType` gives it.
- Several types SHALL select their union.
- A type without a dtype SHALL not compile.

```nim
let df = newDataFrame(series("station", ["N", "S"]), series("bears", [3, 5]),
                      series("weight", [410.5, 380.0]))
echo df.select(col(SomeNumber)).columns
echo df.select(col(float, string)).columns
```

```text
@["bears", "weight"]
@["station", "weight"]
```

#### Scenario: Numeric columns
- **WHEN** `select(col(SomeNumber))` runs on columns `station` (str), `bears` (i64) and `weight` (f64)
- **THEN** the result has columns `bears` and `weight`

#### Scenario: Exact types
- **WHEN** `select(col(float, string))` runs on the same frame
- **THEN** the result has columns `station` and `weight`

#### Scenario: Not a column type
- **WHEN** `col(seq[int])` is compiled
- **THEN** compilation fails

### Requirement: Selecting by name
`col(a, b, ...)` with two or more names, and `col(names)` with an `openArray[string]`,
SHALL return a `Selector` for those columns in that order, and `all()` SHALL select
every column. `col` with one name SHALL keep returning an `Expr`, and a name that starts
with `^` and ends with `$` SHALL be a regex.

```nim
let df = newDataFrame(series("weight_kg", [410.5]), series("weight_lb", [905.0]),
                      series("name", ["Nanuq"]))
echo df.select(col("^weight_.*$")).columns    # regex
echo df.select(col("name", "weight_kg")).columns
echo df.select(all()).columns
let wanted = @["weight_lb", "name"]
echo df.select(col(wanted)).columns
```

```text
@["weight_kg", "weight_lb"]
@["name", "weight_kg"]
@["weight_kg", "weight_lb", "name"]
@["weight_lb", "name"]
```

#### Scenario: Regex
- **WHEN** `select(col("^weight_.*$"))` runs on columns `weight_kg`, `weight_lb` and `name`
- **THEN** the result has columns `weight_kg` and `weight_lb`

#### Scenario: Names from a seq
- **WHEN** `select(col(@["c", "a"]))` runs on columns `a`, `b` and `c`
- **THEN** the result has columns `c` and `a`

### Requirement: Excluding columns
`Selector` SHALL support `exclude(names: varargs[string])`, which removes the named columns
from the selection.

```nim
let df = newDataFrame(series("id", [1]), series("a", [2]), series("b", [3]))
echo df.select(all().exclude("id")).columns
```

```text
@["a", "b"]
```

#### Scenario: All but one
- **WHEN** `select(all().exclude("id"))` runs on columns `id`, `a` and `b`
- **THEN** the result has columns `a` and `b`

### Requirement: Selectors as expressions
A `Selector` SHALL convert to `Expr` automatically. An expression built from it SHALL
apply to every selected column and keep each column's name.

```nim
let df = newDataFrame(series("station", ["N", "N", "S"]), series("bears", [3, 5, 4]),
                      series("cubs", [1, 0, 2]), series("weight", [410.5, 380.0, 300.0]))
echo df.lazy.groupBy(col("station"))
  .agg(col(SomeNumber).exclude("cubs").mean)
  .sort("station").collect
```

```text
shape: (2, 3)
┌─────────┬───────┬────────┐
│ station ┆ bears ┆ weight │
│ ---     ┆ ---   ┆ ---    │
│ str     ┆ f64   ┆ f64    │
╞═════════╪═══════╪════════╡
│ N       ┆ 4.0   ┆ 395.25 │
│ S       ┆ 4.0   ┆ 300.0  │
└─────────┴───────┴────────┘
```

#### Scenario: Mean per group of every numeric column but one
- **WHEN** a frame is grouped by `station` and aggregated with `col(SomeNumber).exclude("cubs").mean`
- **THEN** the result has `station` and one mean column per remaining numeric column, with the original names

### Requirement: Output name suffix and prefix
`Expr` SHALL support `name.suffix(s)` and `name.prefix(s)`, which append or prepend `s` to
the name of every column the expression produces.

```nim
let df = newDataFrame(series("a", [1.0, 3.0]), series("b", [2.0, 4.0]))
echo df.select(col(SomeFloat).mean.name.suffix("_mean"),
               col(SomeFloat).max.name.prefix("max_"))
```

```text
shape: (1, 4)
┌────────┬────────┬───────┬───────┐
│ a_mean ┆ b_mean ┆ max_a ┆ max_b │
│ ---    ┆ ---    ┆ ---   ┆ ---   │
│ f64    ┆ f64    ┆ f64   ┆ f64   │
╞════════╪════════╪═══════╪═══════╡
│ 2.0    ┆ 3.0    ┆ 3.0   ┆ 4.0   │
└────────┴────────┴───────┴───────┘
```

#### Scenario: Two aggregations of one selector
- **WHEN** `agg(col(SomeFloat).mean.name.suffix("_mean"), col(SomeFloat).max.name.suffix("_max"))` runs on float columns `a` and `b`
- **THEN** the result has columns `a_mean`, `b_mean`, `a_max` and `b_max`

### Requirement: Operators on selectors
Arithmetic, comparison and logical operators SHALL accept a selector (`all()`, `col("a", "b")`, `col(SomeNumber)`) on either side, applying to each selected column and keeping its name; a comparison with a value on the left SHALL be mirrored (`0 < x` is `x > 0`), so the result keeps the column's name.

```nim
let df = newDataFrame(series("a", @[1, -1]), series("b", @[0, 2]))
echo df.select((all() > 0).name.suffix(" > 0"))
echo df.select(0 < col("a"))
```

```text
shape: (2, 2)
┌───────┬───────┐
│ a > 0 ┆ b > 0 │
│ ---   ┆ ---   │
│ bool  ┆ bool  │
╞═══════╪═══════╡
│ true  ┆ false │
│ false ┆ true  │
└───────┴───────┘
shape: (2, 1)
┌───────┐
│ a     │
│ ---   │
│ bool  │
╞═══════╡
│ true  │
│ false │
└───────┘
```

#### Scenario: Selector times a number
- **WHEN** `all() * 2` is selected
- **THEN** every column is doubled and keeps its name
