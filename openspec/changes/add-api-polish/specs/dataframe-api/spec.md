# Spec Delta

## MODIFIED Requirements

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
- **THEN** `NanuqError` is raised

#### Scenario: No clash with sequtils
- **WHEN** a module imports `nanuq` and `std/[os, sequtils]` and calls `toSeq(walkFiles("*.csv"))`
- **THEN** it compiles and returns the matching paths

### Requirement: Reading columns by type
Reading as `float` SHALL accept any integer or float column; as `string`, any column,
formatted as Polars does; as `int`, only integer columns; as `bool`, only boolean
columns. A dtype that does not match SHALL raise `NanuqError`.

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
- **THEN** `NanuqError` is raised

#### Scenario: Bool column
- **WHEN** a bool column is read with `toList(df, "d", bool)`
- **THEN** the result holds the column's values

## ADDED Requirements

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
