## MODIFIED Requirements

### Requirement: Interpolation
`e.interpolate()` SHALL fill nulls that lie between two values on a straight line between
them, or with the nearest value for `interpolate(how = Nearest)`;
`e.interpolateBy(by)` SHALL interpolate linearly using the distances in column `by`.
Nulls before the first and after the last value SHALL stay null.

```nim
let df = newDataFrame:
  day: [1, 2, 4, 5]
  temp: [10.0, nil, 16.0, nil]
echo df.withColumns(col.temp.interpolate.alias("linear"),
                    col.temp.interpolateBy("day").alias("by_day"))
```

```text
shape: (4, 4)
┌─────┬──────┬────────┬────────┐
│ day ┆ temp ┆ linear ┆ by_day │
│ --- ┆ ---  ┆ ---    ┆ ---    │
│ i64 ┆ f64  ┆ f64    ┆ f64    │
╞═════╪══════╪════════╪════════╡
│ 1   ┆ 10.0 ┆ 10.0   ┆ 10.0   │
│ 2   ┆ null ┆ 13.0   ┆ 12.0   │
│ 4   ┆ 16.0 ┆ 16.0   ┆ 16.0   │
│ 5   ┆ null ┆ null   ┆ null   │
└─────┴──────┴────────┴────────┘
```

#### Scenario: Integer column
- **WHEN** `interpolate` runs on 1, null, 3
- **THEN** the result is 1.0, 2.0, 3.0
