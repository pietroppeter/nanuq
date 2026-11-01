## ADDED Requirements

### Requirement: Repeating values into lists
`Expr.repeatBy(by)` SHALL repeat each value `by` times into a list, where `by` is an
int, a column name or an expression (Python's `repeat_by`).

```nim
let df = newDataFrame:
  hut: ["Goûter", "Margherita"]
  nights: [2, 1]
echo df.select(col.hut.repeatBy("nights"))
```

```text
```

#### Scenario: Constant count
- **WHEN** `repeatBy(2)` runs on "x"
- **THEN** the result is the list `["x", "x"]`

### Requirement: Seeds as plain ints
`sample` on expressions and on `list` SHALL take the seed as a plain int,
`sample(3, seed = 42)`, as `shuffle` and frame `sample` do; the same seed SHALL give
the same values.

```nim
let df = newDataFrame:
  m: [4806, 4634, 4061, 4506, 4478]
echo df.select(col.m.sample(3, seed = 42)).height
```

```text
```

#### Scenario: Same seed
- **WHEN** `sample(3, seed = 42)` runs twice on the same column
- **THEN** both runs give the same values
