# Spec Delta

## ADDED Requirements

### Requirement: Shape and position aggregations
Expressions SHALL have the aggregations `product`, `mode` (every most frequent value, in
order of appearance), `argMin` and `argMax` (the row index of the first minimum or
maximum), `skew(bias = true)` and `kurtosis(fisher = true, bias = true)`.

```nim
let df = newDataFrame:
  year: [2020, 2021, 2022, 2023]
  oni: [0.5, -1.0, -0.9, 1.9]
echo df.select(col.oni.argMax.alias("warmest_row"),
               col.oni.argMin.alias("coldest_row"), col.oni.skew.round(3).alias("skew"))
```

```text
TBD
```

#### Scenario: Product
- **WHEN** `product` runs on 2, 3, 4
- **THEN** the result is 24

#### Scenario: Several modes
- **WHEN** `mode` runs on 1, 2, 2, 3, 3
- **THEN** the result holds 2 and 3
