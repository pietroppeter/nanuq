# Spec Delta

## MODIFIED Requirements

### Requirement: describe
`describe(percentiles = [0.25, 0.5, 0.75], interpolation = Nearest)` on DataFrame and
LazyFrame SHALL return a DataFrame with a `statistic` column holding `count`,
`null_count`, `mean`, `std`, `min`, one row per percentile (labelled as `25%`) and `max`,
followed by one column per input column: f64 for numeric and boolean columns, str for
the others, and null where a statistic does not apply.

```nim
let df = newDataFrame:
  rider: ["Pogačar", "Seixas", "Van der Poel"]
  wins: [22, 8, nil]
  pro: [true, false, true]
echo df.describe
```

```text
shape: (9, 4)
┌────────────┬──────────────┬──────────┬──────────┐
│ statistic  ┆ rider        ┆ wins     ┆ pro      │
│ ---        ┆ ---          ┆ ---      ┆ ---      │
│ str        ┆ str          ┆ f64      ┆ f64      │
╞════════════╪══════════════╪══════════╪══════════╡
│ count      ┆ 3            ┆ 2.0      ┆ 3.0      │
│ null_count ┆ 0            ┆ 1.0      ┆ 0.0      │
│ mean       ┆ null         ┆ 15.0     ┆ 0.666667 │
│ std        ┆ null         ┆ 9.899495 ┆ null     │
│ min        ┆ Pogačar      ┆ 8.0      ┆ 0.0      │
│ 25%        ┆ null         ┆ 8.0      ┆ null     │
│ 50%        ┆ null         ┆ 22.0     ┆ null     │
│ 75%        ┆ null         ┆ 22.0     ┆ null     │
│ max        ┆ Van der Poel ┆ 22.0     ┆ 1.0      │
└────────────┴──────────────┴──────────┴──────────┘
```

#### Scenario: Custom percentiles
- **WHEN** `describe(percentiles = [0.1, 0.9])` runs
- **THEN** the statistic column holds `count`, `null_count`, `mean`, `std`, `min`, `10%`, `90%` and `max`

#### Scenario: Statistics that do not apply
- **WHEN** a frame with a string and a boolean column is described
- **THEN** mean, std and percentiles are null for the string column, and std and percentiles for the boolean one

#### Scenario: No columns
- **WHEN** `newDataFrame().describe` runs
- **THEN** `PolarsError` is raised
