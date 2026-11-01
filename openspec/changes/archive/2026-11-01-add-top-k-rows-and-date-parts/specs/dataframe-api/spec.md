## MODIFIED Requirements

### Requirement: Expressions and lazy queries
The API SHALL provide `col`, `lit`, arithmetic, comparison and boolean operators on `Expr`
(lifting Nim literals automatically), the aggregations sum, mean, min, max, count, first,
last, nUnique and std, and `alias`. LazyFrame SHALL support select, withColumns, filter,
groupBy/agg, sort, limit, explain and collect. `groupBy` SHALL keep the groups in the
order their keys first appear (Python's `maintain_order=True`, always on). DataFrame SHALL offer eager shortcuts for
select, withColumns, filter and sort.

```nim
let query = penguins().lazy
  .filter(col("body_mass_g").isNotNull)
  .groupBy(col("species"))
  .agg(col("body_mass_g").mean.alias("mass"), col("species").count.alias("n"))
  .sort("mass", descending = true)
echo query.collect          # nothing runs before collect
```

```text
shape: (3, 3)
┌───────────┬─────────────┬─────┐
│ species   ┆ mass        ┆ n   │
│ ---       ┆ ---         ┆ --- │
│ str       ┆ f64         ┆ u32 │
╞═══════════╪═════════════╪═════╡
│ Gentoo    ┆ 5076.01626  ┆ 123 │
│ Chinstrap ┆ 3733.088235 ┆ 68  │
│ Adelie    ┆ 3700.662252 ┆ 151 │
└───────────┴─────────────┴─────┘
```

#### Scenario: Group order
- **WHEN** a frame with keys b, a, b, c is grouped by the key
- **THEN** the groups come out as b, a, c

#### Scenario: Lazy group by
- **WHEN** a LazyFrame is filtered, grouped, aggregated and sorted
- **THEN** nothing runs until `collect`, which returns the resulting DataFrame
