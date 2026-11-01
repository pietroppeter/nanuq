## ADDED Requirements

### Requirement: Top k rows
LazyFrame and DataFrame SHALL support `topK(k, by, reverse = false)` and
`bottomK(k, by, reverse = false)`, returning the `k` whole rows with the largest
(`topK`) or smallest (`bottomK`) values of `by`, in that order. `by` SHALL be a column
name, a list of names, an expression or a list of expressions; with several keys the
later ones break ties. `reverse = true` SHALL swap the direction. Nulls SHALL come last
and ties SHALL keep their original order.

```nim
let events = newDataFrame:
  start: ["1972 MJJ", "1982 AMJ", "1997 AMJ", "2015 MAM", "2023 MJJ"]
  peak: [2.1, 2.2, 2.4, 2.6, 2.0]
echo events.topK(3, by = "peak")
echo events.bottomK(1, by = col.peak)
```

```text
```

#### Scenario: Reverse
- **WHEN** `topK(2, by = "peak", reverse = true)` runs
- **THEN** it returns the same rows as `bottomK(2, by = "peak")`

#### Scenario: k larger than the frame
- **WHEN** `topK(10, by = "peak")` runs on 5 rows
- **THEN** all 5 rows are returned, largest first
