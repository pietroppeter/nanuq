# missing-values Specification

## Purpose
How Nanuq represents missing values (Polars nulls) in its Nim API: building data with
gaps, reading it back, and testing, filling and dropping nulls in queries.

## Requirements

### Requirement: Nulls are read as Option
Reading a column or a cell with the type `Option[T]` SHALL return `none(T)` for each
null and `some(value)` otherwise, for T in int, float, bool and string.

```nim
let df = newDataFrame(series("a", [some(1), none(int), some(3)]))
echo df.toSeq("a", Option[int])
echo df["a", 1, Option[int]]
```

```text
@[some(1), none(int), some(3)]
none(int)
```

#### Scenario: Column with gaps
- **WHEN** a column holds 1, null, 3 and is read with `toSeq(df, "a", Option[int])`
- **THEN** the result is `@[some(1), none(int), some(3)]`

#### Scenario: Single cell
- **WHEN** the null cell is read with `df["a", 1, Option[int]]`
- **THEN** the result is `none(int)`

### Requirement: Plain reads refuse nulls
Reading a column or a cell with a plain type T SHALL raise `NanuqError` if the values
read include a null, and the message SHALL name the column.

```nim
let df = newDataFrame(series("a", [some(1), none(int)]))
try:
  discard df.toSeq("a", int)
except NanuqError as e:
  echo "NanuqError"
```

```text
NanuqError
```

#### Scenario: Column with a null read as int
- **WHEN** a column with one null is read with `toSeq(df, "a", int)`
- **THEN** `NanuqError` is raised before any value is returned, naming column "a"

### Requirement: Inspecting nulls
The API SHALL report the number of nulls in a column and whether it has any.

```nim
let df = newDataFrame(series("a", [some(1), none(int), some(3)]))
echo df.nullCount("a"), " ", df.hasNulls("a")
```

```text
1 true
```

#### Scenario: Counting
- **WHEN** a column of 3 values has 1 null
- **THEN** `nullCount(df, "a")` is 1 and `hasNulls(df, "a")` is true

#### Scenario: No nulls
- **WHEN** a column has no nulls
- **THEN** `nullCount` is 0 and `hasNulls` is false

### Requirement: Building columns with nulls
`series` SHALL accept `openArray[Option[T]]` for int, float, bool and string, storing
`none` as null with the same dtype as the plain version.

```nim
let df = newDataFrame(series("a", [some(1), none(int)]), series("s", [none(string), some("x")]))
echo df
```

```text
shape: (2, 2)
┌──────┬──────┐
│ a    ┆ s    │
│ ---  ┆ ---  │
│ i64  ┆ str  │
╞══════╪══════╡
│ 1    ┆ null │
│ null ┆ x    │
└──────┴──────┘
```

#### Scenario: Round trip
- **WHEN** a DataFrame is built from `series("a", [some(1), none(int)])`
- **THEN** `dtype(df, "a")` is "i64", `nullCount(df, "a")` is 1, and reading it as `Option[int]` gives back the input

### Requirement: CSV null markers
`readCsv` SHALL accept a list of strings to read as null. Without it, behavior is
unchanged: only empty fields are null.

```nim
let path = getTempDir() / "bears.csv"
writeFile(path, "bear,weight\nNanuq,410\nUrsa,NA\n")
echo readCsv(path, nullValues = ["NA"])
```

```text
shape: (2, 2)
┌───────┬────────┐
│ bear  ┆ weight │
│ ---   ┆ ---    │
│ str   ┆ i64    │
╞═══════╪════════╡
│ Nanuq ┆ 410    │
│ Ursa  ┆ null   │
└───────┴────────┘
```

#### Scenario: NA marker
- **WHEN** a CSV file with "NA" in a numeric column is read with `nullValues = @["NA"]`
- **THEN** that column is numeric and the "NA" fields are null

### Requirement: Null expressions
The API SHALL provide `isNull` and `isNotNull` on expressions (giving booleans), and
`fillNull` replacing nulls with a literal or an expression.

```nim
let df = newDataFrame(series("a", [some(1), none(int), some(3)]))
echo df.select(col("a").isNull.alias("missing"), col("a").fillNull(0).alias("filled"))
echo df.filter(col("a").isNotNull).toSeq("a", int)
```

```text
shape: (3, 2)
┌─────────┬────────┐
│ missing ┆ filled │
│ ---     ┆ ---    │
│ bool    ┆ i64    │
╞═════════╪════════╡
│ false   ┆ 1      │
│ true    ┆ 0      │
│ false   ┆ 3      │
└─────────┴────────┘
@[1, 3]
```

#### Scenario: Filter out nulls
- **WHEN** a LazyFrame is filtered with `col("a").isNotNull` and collected
- **THEN** the result has no nulls in column "a"

#### Scenario: Fill nulls
- **WHEN** `withColumns(col("a").fillNull(0))` is applied to a column 1, null, 3
- **THEN** column "a" becomes 1, 0, 3

### Requirement: Dropping rows with nulls
LazyFrame and DataFrame SHALL provide `dropNulls`, removing rows with a null in any
column, or only in the named columns when a subset is given.

```nim
let df = newDataFrame(series("a", [some(1), none(int), some(3)]),
                      series("b", [some("x"), some("y"), none(string)]))
echo df.dropNulls.shape          # any column
echo df.dropNulls("a")           # only column a
```

```text
(1, 2)
shape: (2, 2)
┌─────┬──────┐
│ a   ┆ b    │
│ --- ┆ ---  │
│ i64 ┆ str  │
╞═════╪══════╡
│ 1   ┆ x    │
│ 3   ┆ null │
└─────┴──────┘
```

#### Scenario: Subset
- **WHEN** `dropNulls(["a"])` is applied to rows where "a" has one null and "b" another, in different rows
- **THEN** only the row with the null in "a" is removed
