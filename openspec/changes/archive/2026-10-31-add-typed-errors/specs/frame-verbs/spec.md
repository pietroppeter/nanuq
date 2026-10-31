# Spec Delta

## MODIFIED Requirements

### Requirement: Dropping and renaming columns
LazyFrame and DataFrame SHALL support `drop(columns, strict = true)`, with one column
name or a list of names, and `rename(mapping: openArray[(string, string)], strict = true)`. With `strict = true`, a
column that does not exist SHALL raise `PolarsError`. With `strict = false`, it SHALL be
ignored.

```nim
let df = newDataFrame(series("a", [1]), series("b", [2]), series("c", [3]))
echo df.drop("b").columns                  # one name
echo df.drop(["a", "b"]).columns           # several
echo df.drop("zzz", strict = false).columns
echo df.rename({"a": "x"}).columns
```

```text
@["a", "c"]
@["c"]
@["a", "b", "c"]
@["x", "b", "c"]
```

#### Scenario: Drop
- **WHEN** `df.drop("b")` runs on columns `a`, `b`, `c`
- **THEN** the columns are `a`, `c`, and `df.drop(["a", "b"])` leaves `c`

#### Scenario: Rename
- **WHEN** `df.rename({"a": "x"})` runs on columns `a`, `b`
- **THEN** the columns are `x`, `b`

#### Scenario: Strict
- **WHEN** `df.drop("zzz")` runs
- **THEN** `PolarsError` is raised, and `df.drop("zzz", strict = false)` returns the frame unchanged

### Requirement: Sorting by several keys
LazyFrame and DataFrame SHALL sort by several column names or expressions with
`sort(by, descending: openArray[bool] = [], nullsLast: openArray[bool] = [],
maintainOrder = false)`. An empty list SHALL mean false for every key, and one value
SHALL apply to every key. Another length SHALL raise `PolarsError`. The one-column
`sort(by: string, descending = false, nullsLast = false, maintainOrder = false)` SHALL
remain.

```nim
let df = newDataFrame(series("g", ["b", "a", "b", "a"]), series("v", [1, 2, 3, 4]))
echo df.sort(["g", "v"], descending = [false, true])
```

```text
shape: (4, 2)
┌─────┬─────┐
│ g   ┆ v   │
│ --- ┆ --- │
│ str ┆ i64 │
╞═════╪═════╡
│ a   ┆ 4   │
│ a   ┆ 2   │
│ b   ┆ 3   │
│ b   ┆ 1   │
└─────┴─────┘
```

#### Scenario: Two keys
- **WHEN** a frame is sorted by `["g", "v"]` with `descending = [false, true]`
- **THEN** rows are ordered by `g` ascending and, within each `g`, by `v` descending

#### Scenario: Nulls last
- **WHEN** a column holding null, 2, 1 is sorted with `nullsLast = true`
- **THEN** the order is 1, 2, null

#### Scenario: Length mismatch
- **WHEN** a sort by three keys gets `descending = [true, false]`
- **THEN** `PolarsError` is raised

### Requirement: Sampling rows
DataFrame SHALL support `sample(n, withReplacement = false, shuffle = false, seed =
none(int))` and `sample(fraction, ...)` with the same options. Asking for more rows than
there are without replacement SHALL raise `PolarsError`. The same seed SHALL give the same
rows. `seed` SHALL also accept a plain `int` (`seed = 42`), and `setRandomSeed(seed)` SHALL
seed Polars' global generator, used when no seed is passed.

```nim
let df = newDataFrame(series("n", [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]))
echo df.sample(3, seed = 42) == df.sample(3, seed = 42)   # same seed, same rows
echo df.sample(fraction = 0.5).shape
setRandomSeed(42)
let a = df.sample(4)
setRandomSeed(42)
echo a == df.sample(4)
```

```text
false
(5, 1)
false
```

#### Scenario: Seeded sample
- **WHEN** `sample(3, seed = some(42))` runs twice on the same 10-row frame
- **THEN** both results have 3 rows and are equal

#### Scenario: Global seed
- **WHEN** `setRandomSeed(42)` is called before each of two `sample(4)` calls on the same frame
- **THEN** both results are equal

#### Scenario: Fraction
- **WHEN** `sample(fraction = 0.5)` runs on 10 rows
- **THEN** the result has 5 rows

#### Scenario: Too many rows
- **WHEN** `sample(11)` runs on 10 rows
- **THEN** `PolarsError` is raised
