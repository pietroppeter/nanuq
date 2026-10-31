# Spec Delta

## MODIFIED Requirements

### Requirement: Nulls are read as Option
Reading a column or a cell with the type `Option[T]` SHALL return `none(T)` for each
null and `some(value)` otherwise, for T in int, float, bool and string.

```nim
let df = newDataFrame(series("a", [some(1), none(int), some(3)]))
echo df.toList("a", Option[int])
echo df["a", 1, Option[int]]
```

```text
@[some(1), none(int), some(3)]
none(int)
```

#### Scenario: Column with gaps
- **WHEN** a column holds 1, null, 3 and is read with `toList(df, "a", Option[int])`
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
  discard df.toList("a", int)
except NanuqError as e:
  echo "NanuqError"
```

```text
NanuqError
```

#### Scenario: Column with a null read as int
- **WHEN** a column with one null is read with `toList(df, "a", int)`
- **THEN** `NanuqError` is raised before any value is returned, naming column "a"

### Requirement: Inspecting nulls
The API SHALL report the number of nulls in a column and whether it has any, and SHALL
provide `nullCount` on expressions as an aggregation (u32), usable in `select` and `agg`.

```nim
let df = newDataFrame(series("a", [some(1), none(int), some(3)]))
echo df.nullCount("a"), " ", df.hasNulls("a")
echo df.select(col.a.nullCount.alias("missing"))
```

```text
1 true
shape: (1, 1)
┌─────────┐
│ missing │
│ ---     │
│ u32     │
╞═════════╡
│ 1       │
└─────────┘
```

#### Scenario: Counting
- **WHEN** a column of 3 values has 1 null
- **THEN** `nullCount(df, "a")` is 1 and `hasNulls(df, "a")` is true

#### Scenario: No nulls
- **WHEN** a column has no nulls
- **THEN** `nullCount` is 0 and `hasNulls` is false

#### Scenario: Null count per group
- **WHEN** `groupBy(col.g).agg(col.a.nullCount)` runs on groups with 1 and 0 nulls
- **THEN** the result has 1 and 0 for those groups

### Requirement: Null expressions
The API SHALL provide `isNull` and `isNotNull` on expressions (giving booleans), and
`fillNull` replacing nulls with a literal or an expression.

```nim
let df = newDataFrame(series("a", [some(1), none(int), some(3)]))
echo df.select(col("a").isNull.alias("missing"), col("a").fillNull(0).alias("filled"))
echo df.filter(col("a").isNotNull).toList("a", int)
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
