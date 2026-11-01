# Spec Delta

## ADDED Requirements

### Requirement: Filtering inside expressions
`e.filter(predicate)` SHALL keep the values of `e` where `predicate` is true, so that an
aggregation can run over part of each group.

```nim
let df = newDataFrame:
  rider: ["Pogačar", "Pogačar", "Vingegaard", "Vingegaard"]
  stage: ["TT", "road", "TT", "road"]
  secs: [3120, 15400, 3150, 15390]
echo df.groupBy(col.rider).agg(col.secs.filter(col.stage == "TT").sum.alias("tt_secs"))
  .sort("rider").collect
```

```text
TBD
```

#### Scenario: Conditional sum
- **WHEN** `col.secs.filter(col.stage == "TT").sum` is aggregated per rider
- **THEN** each rider's sum counts only the TT rows
