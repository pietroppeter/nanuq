# Spec Delta

## REMOVED Requirements

### Requirement: Errors as NanuqError
**Reason**: Replaced by typed errors under the base `PolarsError`.
**Migration**: Catch `PolarsError` (or a subtype such as `ColumnNotFoundError`) instead of `NanuqError`.

## ADDED Requirements

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
