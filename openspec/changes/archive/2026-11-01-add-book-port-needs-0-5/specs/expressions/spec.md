## ADDED Requirements

### Requirement: Entropy
`Expr` SHALL support `entropy(base = E, normalize = true)`, an aggregation giving
`-sum(p * ln(p)) / ln(base)`, where `p` are the values (divided by their sum when
`normalize` is true).

```nim
let df = newDataFrame:
  votes: [@[1, 1, 2], @[5]]
echo df.select(col.votes.list.agg(element().entropy).alias("entropy"))
```

```text
```

#### Scenario: One value
- **WHEN** the entropy of a single positive value is computed
- **THEN** the result is 0.0

### Requirement: Row count expression
`len()` with no argument SHALL be an expression counting rows, named `len` (Python's
`pl.len()`); in a group-by it SHALL count the rows of each group.

```nim
let df = newDataFrame:
  team: ["a", "a", "b"]
echo df.groupBy("team").agg(len())
```

```text
```

#### Scenario: Whole frame
- **WHEN** `df.select(len())` runs on 4 rows
- **THEN** the result is one row with `len` = 4
