## ADDED Requirements

### Requirement: Boolean aggregations
`Expr` SHALL support `any(ignoreNulls = true)` and `all(ignoreNulls = true)` on boolean
columns, as aggregations: whether any value, or every value, is true. With
`ignoreNulls = false` they SHALL follow Kleene logic: `any` is null when there are nulls
and no true value, `all` is null when there are nulls and no false value. The `all()`
selector (no arguments) SHALL keep working.

```nim
let df = newDataFrame:
  team: ["a", "a", "b", "b"]
  won: [true, false, true, true]
echo df.groupBy("team").agg(col.won.all.alias("always"), col.won.any.alias("ever"))
```

```text
```

#### Scenario: Kleene logic
- **WHEN** `any(ignoreNulls = false)` runs on false and null
- **THEN** the result is null
