## ADDED Requirements

### Requirement: Every n-th row
LazyFrame and DataFrame SHALL support `gatherEvery(n, offset = 0)`, keeping rows
`offset`, `offset + n`, `offset + 2n`, ... (Python's `gather_every`).

```nim
let df = newDataFrame:
  month: [1, 2, 3, 4, 5, 6]
echo df.gatherEvery(3, offset = 2)
```

```text
```

#### Scenario: Offset past the end
- **WHEN** `gatherEvery(2, offset = 10)` runs on 6 rows
- **THEN** the result has no rows
