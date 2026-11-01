## ADDED Requirements

### Requirement: Null literal
`lit(nil)` SHALL be a null literal (Python's `pl.lit(None)`), usable wherever an
expression is, and `fillNan(nil)` SHALL turn NaN values into nulls.

```nim
let df = newDataFrame:
  x: [1.0, NaN, 3.0]
echo df.select(col.x.fillNan(nil).alias("x"), col.x.fillNan(nil).nullCount.alias("nulls"))
```

```text
```

#### Scenario: Null column
- **WHEN** `select(lit(nil).alias("n"))` runs with another column of 3 rows
- **THEN** `n` holds 3 nulls
