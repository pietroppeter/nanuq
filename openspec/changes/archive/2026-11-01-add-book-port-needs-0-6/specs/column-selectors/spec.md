# Spec Delta

## ADDED Requirements

### Requirement: Operators on selectors
Arithmetic, comparison and logical operators SHALL accept a selector (`all()`, `col("a", "b")`, `col(SomeNumber)`) on either side, applying to each selected column and keeping its name; a comparison with a value on the left SHALL be mirrored (`0 < x` is `x > 0`), so the result keeps the column's name.

```nim
let df = newDataFrame(series("a", @[1, -1]), series("b", @[0, 2]))
echo df.select((all() > 0).name.suffix(" > 0"))
echo df.select(0 < col("a"))
```

```text
TBD
```

#### Scenario: Selector times a number
- **WHEN** `all() * 2` is selected
- **THEN** every column is doubled and keeps its name
