# Spec Delta

## ADDED Requirements

### Requirement: Fixed rolling windows
`rollingSum`, `rollingMean`, `rollingMin`, `rollingMax`, `rollingMedian`, `rollingStd`,
`rollingVar` and `rollingQuantile` SHALL compute their statistic over the last
`windowSize` rows, or over a window centred on each row with `center = true`. A row
SHALL get null until `minSamples` non-null values are in its window (by default
`windowSize`), and `weights`, when given, SHALL multiply the values of each window.

```nim
let df = newDataFrame:
  season: ["NDJ", "DJF", "JFM", "FMA", "MAM"]
  anomaly: [1.9, 2.1, 1.6, 1.0, 0.4]
echo df.withColumns(col.anomaly.rollingMean(3).round(2).alias("mean3"),
                    col.anomaly.rollingMean(3, center = true).round(2).alias("centred"),
                    col.anomaly.rollingMax(2, minSamples = 1).alias("max2"))
```

```text
TBD
```

#### Scenario: Window not full yet
- **WHEN** `rollingSum(3)` runs on 1, 2, 3, 4
- **THEN** the result is null, null, 6, 9

#### Scenario: Weights
- **WHEN** `rollingSum(2, weights = [0.5, 1.0])` runs on 2.0, 4.0
- **THEN** the second value is 5.0

#### Scenario: Invalid window
- **WHEN** `rollingMean(0)` is built
- **THEN** `ValueError` is raised

### Requirement: Time rolling windows
The same functions with a `By` suffix SHALL take a sorted column `by` (temporal or
integer) and a window size as a std/times interval or Polars duration string; the window
of each row SHALL span `windowSize` back from its `by` value, with ends included as
`closed` (`ClosedWindow`, default `Right`) says, and rows SHALL need `minSamples` values
(default 1).

```nim
let df = newDataFrame:
  day: [date(2026, 7, 1), date(2026, 7, 2), date(2026, 7, 5), date(2026, 7, 6)]
  rain: [4, 0, 10, 2]
echo df.withColumns(col.rain.rollingSumBy("day", 3.days).alias("last_3_days"))
```

```text
TBD
```

#### Scenario: Gaps in the dates
- **WHEN** `rollingSumBy("day", 3.days)` runs on July 1, 2, 5, 6 with 4, 0, 10, 2
- **THEN** the result is 4, 4, 10, 12

### Requirement: Exponentially weighted functions
`ewmMean`, `ewmStd` and `ewmVar` SHALL compute exponentially weighted statistics with the
decay given by exactly one of `com`, `span`, `halfLife` or `alpha`, converted to alpha as
Python Polars does, and SHALL take `adjust`, `minSamples` and `ignoreNulls` (and `bias`
for std and var). Giving none or more than one decay parameter SHALL raise `ValueError`.

```nim
let df = newDataFrame:
  temp: [14.0, 15.0, 13.0, 16.0]
echo df.withColumns(col.temp.ewmMean(alpha = 0.5).round(3).alias("ewm"),
                    col.temp.ewmMean(span = 3, adjust = false).round(3).alias("span3"))
```

```text
TBD
```

#### Scenario: Span and alpha agree
- **WHEN** `ewmMean(span = 3)` and `ewmMean(alpha = 0.5)` run on the same column
- **THEN** the results are equal

#### Scenario: Two decay parameters
- **WHEN** `ewmMean(com = 1, alpha = 0.5)` is built
- **THEN** `ValueError` is raised
