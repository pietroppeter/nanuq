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

### Requirement: Errors as NanuqError
Any failing FFI call SHALL raise `NanuqError` carrying the message from Rust.

```nim
let df = newDataFrame(series("a", [1]))
try:
  discard df.select(col("nope"))
except NanuqError as e:
  echo e.msg.splitLines[0]
```

```text
not found: unable to find column "nope"; valid columns: ["a"]
```

#### Scenario: Bad column
- **WHEN** a query selects a column that does not exist
- **THEN** `NanuqError` is raised with the Polars error message

### Requirement: Building and reading data
The API SHALL build a DataFrame from Nim arrays of int, float, bool and string
(`series`, `newDataFrame`), read and write CSV with a header row, and expose `shape`,
`columns`, `dtype`, `head`, `$` (Polars' table format), single cells and whole columns.

```nim
let df = newDataFrame(series("bear", ["Nanuq", "Ursa"]), series("weight", [410.5, 380.0]))
echo df
echo df.shape, " ", df.columns, " ", df["bear", 0, string], " ", df.toSeq("weight", float)
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
- **THEN** `NanuqError` is raised

### Requirement: Reading columns by type
Reading as `float` SHALL accept any integer or float column; as `string`, any column,
formatted as Polars does; as `int`, only integer columns; as `bool`, only boolean
columns. A dtype that does not match SHALL raise `NanuqError`.

```nim
let df = newDataFrame(series("a", [1, 2]))
echo df.toSeq("a", float)     # integers widen to float
echo df.toSeq("a", string)    # any column formats as text
```

```text
@[1.0, 2.0]
@["1", "2"]
```

#### Scenario: Integers read as floats
- **WHEN** an i64 column holding 1, 2 is read with `toSeq(df, "a", float)`
- **THEN** the result is `@[1.0, 2.0]`

#### Scenario: Floats are not truncated to int
- **WHEN** an f64 column is read with `toSeq(df, "a", int)`
- **THEN** `NanuqError` is raised

#### Scenario: Bool column
- **WHEN** a bool column is read with `toSeq(df, "d", bool)`
- **THEN** the result holds the column's values

### Requirement: Expressions and lazy queries
The API SHALL provide `col`, `lit`, arithmetic, comparison and boolean operators on `Expr`
(lifting Nim literals automatically), the aggregations sum, mean, min, max, count, first,
last, nUnique and std, and `alias`. LazyFrame SHALL support select, withColumns, filter,
groupBy/agg, sort, limit, explain and collect. DataFrame SHALL offer eager shortcuts for
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
