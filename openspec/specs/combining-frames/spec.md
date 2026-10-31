# combining-frames Specification

## Purpose
How Nanuq combines frames: joins of two frames on keys (or a cross join), and
concatenation of several frames vertically, horizontally or diagonally.

## Requirements

### Requirement: Joins
The API SHALL join two LazyFrames or two DataFrames with `join`, with `how` one of
a `JoinType`: `Inner` (default), `Left`, `Right`, `Full`, `Semi`, `Anti` or `Cross`. Keys
SHALL be given as `on` (same names on both sides) or `leftOn` and `rightOn`, as column
names or expressions. A cross join SHALL take no keys.

```nim
let bears = newDataFrame(series("k", [1, 2, 3]), series("bear", ["Nanuq", "Ursa", "Kuma"]))
let seen = newDataFrame(series("k", [1, 3]), series("where", ["ice", "shore"]))
echo bears.join(seen, on = ["k"], how = Left)
echo bears.join(seen, on = ["k"], how = Anti)
```

```text
shape: (3, 3)
┌─────┬───────┬───────┐
│ k   ┆ bear  ┆ where │
│ --- ┆ ---   ┆ ---   │
│ i64 ┆ str   ┆ str   │
╞═════╪═══════╪═══════╡
│ 1   ┆ Nanuq ┆ ice   │
│ 2   ┆ Ursa  ┆ null  │
│ 3   ┆ Kuma  ┆ shore │
└─────┴───────┴───────┘
shape: (1, 2)
┌─────┬──────┐
│ k   ┆ bear │
│ --- ┆ ---  │
│ i64 ┆ str  │
╞═════╪══════╡
│ 2   ┆ Ursa │
└─────┴──────┘
```

#### Scenario: Left join
- **WHEN** a frame with keys 1, 2, 3 is left-joined on `k` to a frame with keys 1, 3
- **THEN** the result has three rows, and the right side's columns are null for key 2

#### Scenario: Semi and anti
- **WHEN** the same frames are semi-joined and anti-joined
- **THEN** the semi join keeps the rows with keys 1 and 3, and the anti join keeps the row with key 2, with only the left columns

#### Scenario: Different key names
- **WHEN** frames are joined with `leftOn = ["id"]` and `rightOn = ["station_id"]`
- **THEN** rows are matched on those columns

#### Scenario: Cross join
- **WHEN** a 2-row frame is joined to a 3-row frame with `how = Cross`
- **THEN** the result has 6 rows

#### Scenario: Keys missing
- **WHEN** `join` is called without keys and a join type other than `Cross`
- **THEN** `PolarsError` is raised

### Requirement: Join options
`join` SHALL accept, with Polars' defaults: `suffix` (`"_right"`) for clashing column
names, `validate` (`JoinValidation`: `ManyToMany`, or `ManyToOne`, `OneToMany`, `OneToOne`),
`nullsEqual` (false), `coalesce` (`none(bool)` for Polars' per-join-type default) and
`maintainOrder` (`MaintainOrderJoin`: `None`, or `Left`, `Right`, `LeftRight`,
`RightLeft`).

```nim
let a = newDataFrame(series("k", [1, 2]), series("v", [10, 20]))
let b = newDataFrame(series("k", [1, 2]), series("v", [100, 200]))
echo a.join(b, on = ["k"], suffix = "_b", validate = OneToOne, maintainOrder = Left)
```

```text
shape: (2, 3)
┌─────┬─────┬─────┐
│ k   ┆ v   ┆ v_b │
│ --- ┆ --- ┆ --- │
│ i64 ┆ i64 ┆ i64 │
╞═════╪═════╪═════╡
│ 1   ┆ 10  ┆ 100 │
│ 2   ┆ 20  ┆ 200 │
└─────┴─────┴─────┘
```

#### Scenario: Suffix
- **WHEN** both frames have a non-key column `v` and `suffix = "_b"`
- **THEN** the result has columns `v` and `v_b`

#### Scenario: Validation failure
- **WHEN** the right frame has a duplicate key and `validate = ManyToOne`
- **THEN** `PolarsError` is raised when the query runs

#### Scenario: Null keys
- **WHEN** both frames have a null key, joined with `nullsEqual = true`
- **THEN** the null keys match each other; with the default they don't

#### Scenario: Keep left order
- **WHEN** a left join runs with `maintainOrder = Left`
- **THEN** the result rows follow the left frame's order

### Requirement: Concatenation
The API SHALL concatenate a list of LazyFrames or DataFrames with `concat`, with `how`
a `ConcatMethod`: `Vertical` (default, same schema), `VerticalRelaxed` (cast to
common supertypes), `Horizontal` (side by side), `Diagonal` (union of columns, missing
ones null) or `DiagonalRelaxed`. An empty list SHALL raise `PolarsError`.

```nim
let ab = newDataFrame(series("a", [1]), series("b", [2]))
let bc = newDataFrame(series("b", [3]), series("c", [4]))
echo concat([ab, bc], how = Diagonal)
```

```text
shape: (2, 3)
┌──────┬─────┬──────┐
│ a    ┆ b   ┆ c    │
│ ---  ┆ --- ┆ ---  │
│ i64  ┆ i64 ┆ i64  │
╞══════╪═════╪══════╡
│ 1    ┆ 2   ┆ null │
│ null ┆ 3   ┆ 4    │
└──────┴─────┴──────┘
```

#### Scenario: Vertical
- **WHEN** two frames with the same columns and 2 and 3 rows are concatenated
- **THEN** the result has 5 rows in input order

#### Scenario: Vertical with different types
- **WHEN** frames whose column `a` is i64 in one and f64 in the other are concatenated
- **THEN** `Vertical` raises `PolarsError` and `VerticalRelaxed` returns `a` as f64

#### Scenario: Diagonal
- **WHEN** a frame with columns `a, b` and one with `b, c` are concatenated diagonally
- **THEN** the result has columns `a, b, c`, with nulls where a frame had no column

#### Scenario: Horizontal
- **WHEN** a frame with column `a` and one with column `b` are concatenated horizontally
- **THEN** the result has columns `a` and `b`
