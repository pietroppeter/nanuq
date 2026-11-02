# Spec Delta

## ADDED Requirements

### Requirement: Group keys by name
The `groupBy` parameter of `rolling` and `groupByDynamic` SHALL take a column name, several names, an expression or several expressions (`groupBy = "store"`, `["store", "aisle"]`, `[col("store")]`).

```nim
let df = newDataFrame(series("day", @[1, 2, 3, 1, 2]), series("store", @["a", "a", "a", "b", "b"]),
                      series("sales", @[1, 2, 3, 10, 20]))
echo df.rolling("day", "2i", groupBy = "store").agg(col("sales").sum)
```

```text
TBD
```

#### Scenario: Expressions still work
- **WHEN** `groupBy = [col("store")]` is passed
- **THEN** the result is the same as with `groupBy = "store"`
