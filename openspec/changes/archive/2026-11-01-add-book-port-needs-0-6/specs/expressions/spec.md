# Spec Delta

## ADDED Requirements

### Requirement: Several window keys and selector concatenation
`over` SHALL take several column names as separate arguments, and `concatStr` SHALL take selectors, expanding them to their columns.

```nim
let df = newDataFrame(series("c", @["x", "x", "y"]), series("b", @["p", "p", "q"]))
echo df.select(concatStr([all()], "-").alias("s"), lit(1).sum.over("c", "b").alias("n"))
```

```text
TBD
```

#### Scenario: Two keys
- **WHEN** `col("v").sum.over("c", "b")` is selected
- **THEN** each row gets the sum of its (c, b) group
