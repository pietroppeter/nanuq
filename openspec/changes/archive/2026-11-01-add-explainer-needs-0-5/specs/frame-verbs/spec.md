## ADDED Requirements

### Requirement: Several filter predicates
DataFrame and LazyFrame `filter` SHALL take several predicates, `filter(a, b, ...)`,
keeping the rows where all of them hold (Python's `filter(a, b)`).

```nim
let df = newDataFrame:
  peak: ["Mont Blanc", "Monte Rosa", "Gran Paradiso"]
  m: [4806, 4634, 4061]
  italy: [true, true, true]
echo df.filter(col.m > 4500, col.italy)
```

```text
```

#### Scenario: All must hold
- **WHEN** a row meets one predicate but not the other
- **THEN** it is dropped

### Requirement: Group order parameter
`groupBy` on DataFrame and LazyFrame SHALL accept `maintainOrder` (Python's
`maintain_order`), with names or expressions; the groups SHALL keep the order their keys
first appear whatever its value.

```nim
let df = newDataFrame:
  country: ["CH", "IT", "CH"]
  m: [4634, 4061, 4506]
echo df.groupBy("country", maintainOrder = true).agg(col.m.max)
```

```text
```

#### Scenario: Order kept
- **WHEN** keys appear as CH, IT, CH and `maintainOrder = false` is passed
- **THEN** the groups come out as CH, IT
