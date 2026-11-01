# Spec Delta

## ADDED Requirements

### Requirement: Describe prints temporal values as Python
`describe` SHALL print Datetime statistics and the mean of a Date column as `YYYY-MM-DD HH:MM:SS`, with a fraction only when it is not zero.

```nim
let df = newDataFrame(series("d", @[date(1986, 9, 1), date(1986, 9, 7)]))
echo df.describe
```

```text
TBD
```

#### Scenario: Date mean
- **WHEN** the mean of 1986-09-01 and 1986-09-07 is described
- **THEN** it reads `1986-09-04 00:00:00`
