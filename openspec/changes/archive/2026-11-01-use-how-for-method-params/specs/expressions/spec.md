## MODIFIED Requirements

### Requirement: Ranking
`Expr` SHALL support `rank(how = Average, descending = false, seed = none(int))`
with a pure enum `RankMethod` (`Average`, `Min`, `Max`, `Dense`, `Ordinal`, `Random`),
giving each value its rank from 1. Ties SHALL be handled as Polars does: `Average` gives
tied values the mean of their ranks (f64), `Min` and `Max` the lowest or highest (u32),
`Dense` leaves no gaps after ties, and `Ordinal` breaks ties by position. `seed` SHALL
make `Random` repeatable. Nulls SHALL stay null.

```nim
let roll = newDataFrame:
  rider: ["Merckx", "Pogačar", "De Vlaeminck", "Van Looy", "Kelly"]
  monuments: [19, 13, 11, 8, 9]
echo roll.select(col.rider, col.monuments,
                 col.monuments.rank(Min, descending = true).alias("place"),
                 col.monuments.rank.alias("avg"))
```

```text
shape: (5, 4)
┌──────────────┬───────────┬───────┬─────┐
│ rider        ┆ monuments ┆ place ┆ avg │
│ ---          ┆ ---       ┆ ---   ┆ --- │
│ str          ┆ i64       ┆ u32   ┆ f64 │
╞══════════════╪═══════════╪═══════╪═════╡
│ Merckx       ┆ 19        ┆ 1     ┆ 5.0 │
│ Pogačar      ┆ 13        ┆ 2     ┆ 4.0 │
│ De Vlaeminck ┆ 11        ┆ 3     ┆ 3.0 │
│ Van Looy     ┆ 8         ┆ 5     ┆ 1.0 │
│ Kelly        ┆ 9         ┆ 4     ┆ 2.0 │
└──────────────┴───────────┴───────┴─────┘
```

#### Scenario: Shared places
- **WHEN** `rank(Min, descending = true)` runs over 9, 9, 7
- **THEN** the result is 1, 1, 3

#### Scenario: Dense
- **WHEN** `rank(Dense)` runs over 9, 9, 7
- **THEN** the result is 2, 2, 1

#### Scenario: Average
- **WHEN** `rank()` runs over 9, 9, 7
- **THEN** the result is 2.5, 2.5, 1.0 with dtype f64
