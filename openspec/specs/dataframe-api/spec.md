# dataframe-api Specification

## Purpose
The Nim-facing API in `src/nanuq.nim`: DataFrame, LazyFrame and Expr values backed by
Polars, with automatic memory management and Nim exceptions.

## Requirements

### Requirement: Automatic memory management
`DataFrame`, `LazyFrame`, `Expr` and `Series` SHALL be Nim `ref` types whose destructors
free the underlying Rust object when the last reference goes away. Copying the inner
objects SHALL be a compile-time error.

```nim
var a = newDataFrame(series("n", [1, 2]))
let b = a          # same Polars frame, no copy
a = nil            # still alive through b
echo b.shape       # freed when b goes out of scope
```

```text
(2, 1)
```

#### Scenario: Shared value
- **WHEN** two Nim variables refer to the same DataFrame
- **THEN** the Rust object is freed once, after both go out of scope

### Requirement: Building and reading data
The API SHALL build a DataFrame from Nim arrays of int, float, bool and string
(`series`, `newDataFrame`), read and write CSV with a header row, and expose `shape`,
`columns`, `dtype`, `head`, `$` (Polars' table format), single cells and whole columns
(`toList`).

```nim
let df = newDataFrame(series("bear", ["Nanuq", "Ursa"]), series("weight", [410.5, 380.0]))
echo df
echo df.shape, " ", df.columns, " ", df["bear", 0, string], " ", df.toList("weight", float)
```

```text
shape: (2, 2)
┌───────┬────────┐
│ bear  ┆ weight │
│ ---   ┆ ---    │
│ str   ┆ f64    │
╞═══════╪════════╡
│ Nanuq ┆ 410.5  │
│ Ursa  ┆ 380.0  │
└───────┴────────┘
(2, 2) @["bear", "weight"] Nanuq @[410.5, 380.0]
```

#### Scenario: Columns of different lengths
- **WHEN** `newDataFrame` gets series of different lengths
- **THEN** `PolarsError` is raised

#### Scenario: No clash with sequtils
- **WHEN** a module imports `nanuq` and `std/[os, sequtils]` and calls `toSeq(walkFiles("*.csv"))`
- **THEN** it compiles and returns the matching paths

### Requirement: Reading columns by type
Reading as `float` SHALL accept any integer or float column; as `string`, any column,
formatted as Polars does; as `int`, only integer columns; as `bool`, only boolean
columns. A dtype that does not match SHALL raise `PolarsError`.

```nim
let df = newDataFrame(series("a", [1, 2]))
echo df.toList("a", float)     # integers widen to float
echo df.toList("a", string)    # any column formats as text
```

```text
@[1.0, 2.0]
@["1", "2"]
```

#### Scenario: Integers read as floats
- **WHEN** an i64 column holding 1, 2 is read with `toList(df, "a", float)`
- **THEN** the result is `@[1.0, 2.0]`

#### Scenario: Floats are not truncated to int
- **WHEN** an f64 column is read with `toList(df, "a", int)`
- **THEN** `PolarsError` is raised

#### Scenario: Bool column
- **WHEN** a bool column is read with `toList(df, "d", bool)`
- **THEN** the result holds the column's values

### Requirement: Expressions and lazy queries
The API SHALL provide `col`, `lit`, arithmetic, comparison and boolean operators on `Expr`
(lifting Nim literals automatically), the aggregations sum, mean, min, max, count, first,
last, nUnique and std, and `alias`. LazyFrame SHALL support select, withColumns, filter,
groupBy/agg, sort, limit, explain and collect. `groupBy` SHALL take key expressions or
column names (`groupBy("species")`), and SHALL keep the groups in the order their keys
first appear (Python's `maintain_order=True`, always on). On a DataFrame, `groupBy`,
`groupByDynamic` and `rolling` followed by `agg` SHALL return a DataFrame, as in Python;
on a LazyFrame they return a LazyFrame. DataFrame SHALL offer eager shortcuts for
select, withColumns, filter and sort.

```nim
let query = penguins().lazy
  .filter(col("body_mass_g").isNotNull)
  .groupBy(col("species"))
  .agg(col("body_mass_g").mean.alias("mass"), col("species").count.alias("n"))
  .sort("mass", descending = true)
echo query.collect          # nothing runs before collect
```

```text
shape: (3, 3)
┌───────────┬─────────────┬─────┐
│ species   ┆ mass        ┆ n   │
│ ---       ┆ ---         ┆ --- │
│ str       ┆ f64         ┆ u32 │
╞═══════════╪═════════════╪═════╡
│ Gentoo    ┆ 5076.01626  ┆ 123 │
│ Chinstrap ┆ 3733.088235 ┆ 68  │
│ Adelie    ┆ 3700.662252 ┆ 151 │
└───────────┴─────────────┴─────┘
```

#### Scenario: Eager group by
- **WHEN** `df.groupBy("a").agg(col.v.sum)` runs on a DataFrame
- **THEN** the result is a DataFrame, with no `collect` needed

#### Scenario: Keys by name
- **WHEN** `df.groupBy("a", "b")` is followed by `agg`
- **THEN** it groups as `df.groupBy(col.a, col.b)` does

#### Scenario: Group order
- **WHEN** a frame with keys b, a, b, c is grouped by the key
- **THEN** the groups come out as b, a, c

#### Scenario: Lazy group by
- **WHEN** a LazyFrame is filtered, grouped, aggregated and sorted
- **THEN** nothing runs until `collect`, which returns the resulting DataFrame

### Requirement: HTML tables
`toHtml(df, maxRows = 10, maxCols = 75)` SHALL return the HTML that Python Polars'
`DataFrame._repr_html_` returns for the same data and limits: shape line, names and
dtypes header rows, cells formatted by Polars, and `…` rows and columns when truncated.

#### Scenario: Same as Python
- **WHEN** `toHtml` is called on `penguins()`
- **THEN** the result equals what Python Polars' `_repr_html_` returns for the same CSV read with `null_values="NA"`

#### Scenario: Truncation
- **WHEN** a DataFrame with 344 rows is rendered with `maxRows = 10`
- **THEN** the body shows rows 0 to 4, a `…` row, and rows 339 to 343

#### Scenario: Escaping and nulls
- **WHEN** a string cell holds `<b>` and another cell is null
- **THEN** the first is shown as `"&lt;b&gt;"` and the second as `null`

### Requirement: Block syntax for building a DataFrame
`newDataFrame` SHALL accept a block of `name: [values]` lines and build one column per
line, in order, as `series(name, values)` would. A name SHALL be a Nim identifier or a
string literal. A `nil` inside the brackets SHALL be a missing value, and the column
SHALL then have the type of its other values. `newDataFrame` SHALL keep accepting series
(`newDataFrame(series(...), ...)`, a seq of series, or none at all).

```nim
let df = newDataFrame:
  rider: ["Pogačar", "Seixas", "Vingegaard"]
  wins: [22, 8, nil]
  "win %": [0.31, 0.12, 0.05]
echo df
```

```text
shape: (3, 3)
┌────────────┬──────┬───────┐
│ rider      ┆ wins ┆ win % │
│ ---        ┆ ---  ┆ ---   │
│ str        ┆ i64  ┆ f64   │
╞════════════╪══════╪═══════╡
│ Pogačar    ┆ 22   ┆ 0.31  │
│ Seixas     ┆ 8    ┆ 0.12  │
│ Vingegaard ┆ null ┆ 0.05  │
└────────────┴──────┴───────┘
```

#### Scenario: Same frame as series
- **WHEN** a frame is built with the block syntax and the same frame with `series` calls
- **THEN** both have the same columns, dtypes and values

#### Scenario: nil is a null
- **WHEN** a line reads `wins: [22, nil]`
- **THEN** column "wins" is i64 with values 22 and null

#### Scenario: Only nil
- **WHEN** a line reads `wins: [nil, nil]`
- **THEN** the program fails to compile

#### Scenario: Empty frame
- **WHEN** `newDataFrame()` is called
- **THEN** the result has shape (0, 0)

### Requirement: Column shorthand
`col.name` SHALL be the same expression as `col("name")` for any column name that is a
Nim identifier and not taken by Nim first (`type`, and generic `system` procs such as
`repr`). Every other form of `col` SHALL keep working: `col("a")`, `col("a", "b")`,
`col(SomeNumber)` and `col(float, int)`. User code SHALL need no pragma to use them.

```nim
let df = newDataFrame:
  race: ["Sanremo", "Lombardia"]
  "end": [1, 2]
echo df.select(col.race, col.end, col("race", "end").count.name.suffix("_n"))
```

```text
shape: (2, 4)
┌───────────┬─────┬────────┬───────┐
│ race      ┆ end ┆ race_n ┆ end_n │
│ ---       ┆ --- ┆ ---    ┆ ---   │
│ str       ┆ i64 ┆ u32    ┆ u32   │
╞═══════════╪═════╪════════╪═══════╡
│ Sanremo   ┆ 1   ┆ 2      ┆ 2     │
│ Lombardia ┆ 2   ┆ 2      ┆ 2     │
└───────────┴─────┴────────┴───────┘
```

#### Scenario: Same plan
- **WHEN** `$col.race` and `$col("race")` are compared
- **THEN** they are equal

#### Scenario: Names that are procs
- **WHEN** `col.len` and `col.min` are used
- **THEN** they select the columns "len" and "min"

### Requirement: True division
`/` on expressions SHALL be Polars' true division: the result SHALL be a float column
even when both sides are integers, and a division by zero SHALL give `inf` or `NaN`, not
null. `div` SHALL stay floor division.

```nim
let df = newDataFrame:
  seconds: [7200, 5400, 0]
echo df.select(col.seconds, (col.seconds / 3600).alias("hours"),
               (col.seconds div 3600).alias("whole"), (col.seconds / 0).alias("by_zero"))
```

```text
shape: (3, 4)
┌─────────┬───────┬───────┬─────────┐
│ seconds ┆ hours ┆ whole ┆ by_zero │
│ ---     ┆ ---   ┆ ---   ┆ ---     │
│ i64     ┆ f64   ┆ i64   ┆ f64     │
╞═════════╪═══════╪═══════╪═════════╡
│ 7200    ┆ 2.0   ┆ 2     ┆ inf     │
│ 5400    ┆ 1.5   ┆ 1     ┆ inf     │
│ 0       ┆ 0.0   ┆ 0     ┆ NaN     │
└─────────┴───────┴───────┴─────────┘
```

#### Scenario: Integers divide to a float
- **WHEN** `lit(7) / 2` is evaluated
- **THEN** the result is 3.5 with dtype f64

#### Scenario: Floor division unchanged
- **WHEN** `lit(7) div 2` is evaluated
- **THEN** the result is 3 with dtype i64

### Requirement: Errors as PolarsError
Any failing FFI call SHALL raise a `PolarsError`, or Nim's `IOError` for IO failures,
carrying the message from Rust. The type SHALL follow the Rust `PolarsError` variant:
`ColumnNotFoundError`, `ComputeError`, `DuplicateError`, `InvalidOperationError`,
`NoDataError`, `OutOfBoundsError`, `SchemaError`, `SchemaFieldNotFoundError`,
`ShapeError`, `StructFieldNotFoundError` and `SqlError`, all subtypes of `PolarsError`.

```nim
let df = newDataFrame(series("a", [1]), series("s", ["x"]))
try:
  discard df.select(col("nope"))
except ColumnNotFoundError as e:
  echo e.msg.splitLines[0]
try:
  discard df.select(col("s").cast(int))
except PolarsError as e:
  echo e.name
try:
  discard readCsv("no/such/file.csv")
except IOError:
  echo "IOError"
```

```text
not found: unable to find column "nope"; valid columns: ["a", "s"]
InvalidOperationError
IOError
```

#### Scenario: Bad column
- **WHEN** a query selects a column that does not exist
- **THEN** `ColumnNotFoundError` is raised with the Polars error message

#### Scenario: Subtypes are PolarsErrors
- **WHEN** a strict cast fails and the code catches `PolarsError`
- **THEN** the handler runs, with an `InvalidOperationError`

#### Scenario: Missing file
- **WHEN** `readCsv` gets a path that does not exist
- **THEN** `IOError` is raised, and it is not a `PolarsError`
