## MODIFIED Requirements

### Requirement: Correlation
`corr(a, b, how = Pearson)` SHALL return the Pearson or Spearman
correlation of two columns as an aggregation, and `cov(a, b, ddof = 1)` their covariance.

```nim
let df = newDataFrame:
  oni: [-1.0, 0.0, 0.5, 2.0]
  world: [14.6, 14.8, 14.9, 15.2]
echo df.select(corr("oni", "world").round(3).alias("pearson"),
               corr("oni", "world", how = Spearman).alias("spearman"))
```

```text
shape: (1, 2)
┌─────────┬──────────┐
│ pearson ┆ spearman │
│ ---     ┆ ---      │
│ f64     ┆ f64      │
╞═════════╪══════════╡
│ 1.0     ┆ 1.0      │
└─────────┴──────────┘
```

#### Scenario: Perfect correlation
- **WHEN** `corr` runs on 1, 2, 3 and 2, 4, 6
- **THEN** the result is 1.0
