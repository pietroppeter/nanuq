# Spec Delta

## ADDED Requirements

### Requirement: Interpolation
`e.interpolate()` SHALL fill nulls that lie between two values on a straight line between
them, or with the nearest value for `interpolate(InterpolationMethod.Nearest)`;
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
TBD
```

#### Scenario: Integer column
- **WHEN** `interpolate` runs on 1, null, 3
- **THEN** the result is 1.0, 2.0, 3.0
