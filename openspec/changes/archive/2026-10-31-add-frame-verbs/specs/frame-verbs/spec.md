# Spec Delta

## ADDED Requirements

### Requirement: Dropping and renaming columns
LazyFrame and DataFrame SHALL support `drop(columns, strict = true)`, with one column
name or a list of names, and `rename(mapping: openArray[(string, string)], strict = true)`. With `strict = true`, a
column that does not exist SHALL raise `NanuqError`. With `strict = false`, it SHALL be
ignored.

#### Scenario: Drop
- **WHEN** `df.drop("b")` runs on columns `a`, `b`, `c`
- **THEN** the columns are `a`, `c`, and `df.drop(["a", "b"])` leaves `c`

#### Scenario: Rename
- **WHEN** `df.rename({"a": "x"})` runs on columns `a`, `b`
- **THEN** the columns are `x`, `b`

#### Scenario: Strict
- **WHEN** `df.drop("zzz")` runs
- **THEN** `NanuqError` is raised, and `df.drop("zzz", strict = false)` returns the frame unchanged

### Requirement: Row windows
LazyFrame and DataFrame SHALL support `head(n = 5)`, `tail(n = 5)`, `slice(offset)` and
`slice(offset, length)`. A negative offset SHALL count from the end. `reverse()` SHALL
reverse the row order.

#### Scenario: Tail
- **WHEN** `tail(2)` runs on rows 1 to 5
- **THEN** the result is rows 4 and 5

#### Scenario: Slice from the end
- **WHEN** `slice(-3, 2)` runs on rows 1 to 5
- **THEN** the result is rows 3 and 4

#### Scenario: Slice to the end
- **WHEN** `slice(1)` runs on rows 1 to 5
- **THEN** the result is rows 2 to 5

### Requirement: Unique rows
LazyFrame and DataFrame SHALL support `unique(subset = [], keep, maintainOrder = false)`,
with one column name or a list of names, judging duplicates on all columns when the
subset is empty. `keep` is a pure
enum `UniqueKeepStrategy` (`Any` (default), `First`, `Last`, `None`). With
`maintainOrder = true`, the rows SHALL keep their original order.

#### Scenario: Keep first
- **WHEN** `unique("k", keep = First, maintainOrder = true)` runs on keys a, b, a with values 1, 2, 3
- **THEN** the result is (a, 1), (b, 2)

#### Scenario: Keep none
- **WHEN** the same frame is made unique on `k` with `keep = None`
- **THEN** only (b, 2) remains

### Requirement: Row index
LazyFrame and DataFrame SHALL support `withRowIndex(name = "index", offset = 0)`, which
adds an unsigned integer column with that name as the first column, counting from
`offset`.

#### Scenario: Offset
- **WHEN** `withRowIndex("n", offset = 1)` runs on three rows
- **THEN** the first column is `n` with values 1, 2, 3

### Requirement: Sorting by several keys
LazyFrame and DataFrame SHALL sort by several column names or expressions with
`sort(by, descending: openArray[bool] = [], nullsLast: openArray[bool] = [],
maintainOrder = false)`. An empty list SHALL mean false for every key, and one value
SHALL apply to every key. Another length SHALL raise `NanuqError`. The one-column
`sort(by: string, descending = false, nullsLast = false, maintainOrder = false)` SHALL
remain.

#### Scenario: Two keys
- **WHEN** a frame is sorted by `["g", "v"]` with `descending = [false, true]`
- **THEN** rows are ordered by `g` ascending and, within each `g`, by `v` descending

#### Scenario: Nulls last
- **WHEN** a column holding null, 2, 1 is sorted with `nullsLast = true`
- **THEN** the order is 1, 2, null

#### Scenario: Length mismatch
- **WHEN** a sort by three keys gets `descending = [true, false]`
- **THEN** `NanuqError` is raised

### Requirement: Sampling rows
DataFrame SHALL support `sample(n, withReplacement = false, shuffle = false, seed =
none(int))` and `sample(fraction, ...)` with the same options. Asking for more rows than
there are without replacement SHALL raise `NanuqError`. The same seed SHALL give the same
rows.

#### Scenario: Seeded sample
- **WHEN** `sample(3, seed = some(42))` runs twice on the same 10-row frame
- **THEN** both results have 3 rows and are equal

#### Scenario: Fraction
- **WHEN** `sample(fraction = 0.5)` runs on 10 rows
- **THEN** the result has 5 rows

#### Scenario: Too many rows
- **WHEN** `sample(11)` runs on 10 rows
- **THEN** `NanuqError` is raised
