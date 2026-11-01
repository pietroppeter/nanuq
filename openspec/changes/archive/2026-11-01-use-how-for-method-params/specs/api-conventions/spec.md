## ADDED Requirements

### Requirement: Python's `method` parameter is `how`
`method` is a Nim keyword, so no parameter can have that name. Where Python Polars has a
`method` parameter that picks a variant from a closed set, Nanuq SHALL call it `how`, the
name Polars itself uses for `join` and `concat`. This applies to `rank`, `corr` and
`interpolate`. Where Python uses another name (`quantile`'s `interpolation`), Nanuq SHALL
keep Python's name.

```nim
let df = newDataFrame:
  x: [1.0, 2.0, 2.0, 4.0]
  y: [1.0, 4.0, 4.0, 16.0]
echo df.select(col.x.rank(how = Dense).alias("dense"),
               col.x.rank(Min).alias("min"))
echo df.select(corr("x", "y", how = Spearman).alias("spearman"))
```

```text
shape: (4, 2)
┌───────┬─────┐
│ dense ┆ min │
│ ---   ┆ --- │
│ u32   ┆ u32 │
╞═══════╪═════╡
│ 1     ┆ 1   │
│ 2     ┆ 2   │
│ 2     ┆ 2   │
│ 3     ┆ 4   │
└───────┴─────┘
shape: (1, 1)
┌──────────┐
│ spearman │
│ ---      │
│ f64      │
╞══════════╡
│ 1.0      │
└──────────┘
```

#### Scenario: Named variant
- **WHEN** user code writes `corr("x", "y", how = Spearman)` or `rank(how = Dense)`
- **THEN** it compiles and picks that variant

#### Scenario: Positional variant
- **WHEN** user code writes `rank(Min)` or `corr("x", "y", Spearman)`
- **THEN** it means the same as naming `how`
