## ADDED Requirements

### Requirement: Structs from column names
`asStruct` SHALL also take column names: `asStruct("a", "b")` is
`asStruct(col("a"), col("b"))` (Python's `pl.struct("a", "b")`).

```nim
let df = newDataFrame:
  bear: ["Ada", "Bo"]
  kg: [410, 380]
echo df.select(asStruct("bear", "kg").alias("s"))
```

```text
```

#### Scenario: Field names
- **WHEN** `asStruct("bear", "kg")` is selected
- **THEN** the struct has the fields bear and kg
