# Spec Delta

## ADDED Requirements

### Requirement: Dynamic group-by
`groupByDynamic(indexColumn, every, period, offset, ...)` on a DataFrame or LazyFrame
SHALL group the rows of the sorted `indexColumn` into windows that start every `every`,
span `period` (default `every`) and are shifted by `offset`, labelled as `label` says,
and `agg` SHALL aggregate each window. Intervals SHALL be std/times intervals or Polars
duration strings; `groupBy` SHALL group within the windows.

```nim
let df = newDataFrame:
  day: [date(2026, 1, 1), date(2026, 1, 20), date(2026, 2, 3), date(2026, 3, 30)]
  rain: [12, 3, 40, 7]
echo df.groupByDynamic("day", every = 1.months).agg(col.rain.sum).collect
```

```text
TBD
```

#### Scenario: Overlapping windows
- **WHEN** `groupByDynamic("day", every = 1.months, period = 3.months)` aggregates monthly rows
- **THEN** each window sums three months of rows

#### Scenario: Boundaries
- **WHEN** `includeBoundaries = true`
- **THEN** the result has `_lower_boundary` and `_upper_boundary` columns

### Requirement: Rolling group-by
`rolling(indexColumn, period, offset, closed = Right, groupBy)` SHALL make one group per
row, holding the rows whose `indexColumn` lies in the `period` up to that row's value
(shifted by `offset`), and `agg` SHALL aggregate each group.

```nim
let df = newDataFrame:
  day: [date(2026, 7, 1), date(2026, 7, 2), date(2026, 7, 5)]
  rain: [4, 0, 10]
echo df.rolling("day", period = 3.days).agg(col.rain.sum.alias("rain_3d")).collect
```

```text
TBD
```

#### Scenario: Gap in the dates
- **WHEN** rows on July 1, 2 and 5 are grouped with `period = 3.days`
- **THEN** the July 5 group holds only the July 5 row

### Requirement: As-of join
`joinAsof(other, on, ...)` (or `leftOn` and `rightOn`) SHALL join each left row to one
right row by a sorted key: the last one at or before it (`Backward`), the first one at or
after it (`Forward`) or the closest (`Nearest`), only within `tolerance` when given and
only among rows with equal `by` columns; rows without a match SHALL get nulls.

```nim
let events = newDataFrame:
  day: [date(2026, 1, 15), date(2026, 3, 2)]
  event: ["flood", "drought"]
let oni = newDataFrame:
  month: [date(2026, 1, 1), date(2026, 2, 1), date(2026, 3, 1)]
  oni: [1.8, 1.5, 1.1]
echo events.joinAsof(oni, leftOn = "day", rightOn = "month")
```

```text
TBD
```

#### Scenario: Tolerance
- **WHEN** the nearest earlier right row is 2 days before and `tolerance = 1.days`
- **THEN** the left row gets nulls

#### Scenario: Missing keys
- **WHEN** `joinAsof` is called without `on` and without `leftOn` and `rightOn`
- **THEN** `ValueError` is raised
