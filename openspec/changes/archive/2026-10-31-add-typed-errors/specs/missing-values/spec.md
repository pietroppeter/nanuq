# Spec Delta

## MODIFIED Requirements

### Requirement: Plain reads refuse nulls
Reading a column or a cell with a plain type T SHALL raise `InvalidOperationError` if the values
read include a null, and the message SHALL name the column.

```nim
let df = newDataFrame(series("a", [some(1), none(int)]))
try:
  discard df.toList("a", int)
except PolarsError as e:
  echo e.name
```

```text
InvalidOperationError
```

#### Scenario: Column with a null read as int
- **WHEN** a column with one null is read with `toList(df, "a", int)`
- **THEN** `InvalidOperationError` is raised before any value is returned, naming column "a"
