## MODIFIED Requirements

### Requirement: As-of join
`joinAsof(other, on, ...)` (or `leftOn` and `rightOn`) SHALL join each left row to one
right row by a sorted key: the last one at or before it (`Backward`), the first one at or
after it (`Forward`) or the closest (`Nearest`), only within `tolerance` when given and
only among rows with equal `by` columns; rows without a match SHALL get nulls. With
`coalesce = false` the right key column SHALL be kept (with `suffix` if its name is
taken), showing which right row matched.

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
shape: (2, 4)
┌────────────┬─────────┬────────────┬─────┐
│ day        ┆ event   ┆ month      ┆ oni │
│ ---        ┆ ---     ┆ ---        ┆ --- │
│ date       ┆ str     ┆ date       ┆ f64 │
╞════════════╪═════════╪════════════╪═════╡
│ 2026-01-15 ┆ flood   ┆ 2026-01-01 ┆ 1.8 │
│ 2026-03-02 ┆ drought ┆ 2026-03-01 ┆ 1.1 │
└────────────┴─────────┴────────────┴─────┘
```

#### Scenario: Tolerance
- **WHEN** the nearest earlier right row is 2 days before and `tolerance = 1.days`
- **THEN** the left row gets nulls

#### Scenario: Keep the right key
- **WHEN** `joinAsof(other, on = "t", coalesce = false)` runs
- **THEN** the result has both `t` and `t_right`

#### Scenario: Missing keys
- **WHEN** `joinAsof` is called without `on` and without `leftOn` and `rightOn`
- **THEN** `ValueError` is raised
