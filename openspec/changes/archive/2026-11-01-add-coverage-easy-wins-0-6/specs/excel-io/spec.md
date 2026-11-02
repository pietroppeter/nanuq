# Spec Delta

## ADDED Requirements

### Requirement: Reading OpenDocument
`readOds` SHALL read a sheet of an .ods file with the options of `readExcel`.

```nim
echo readOds("tests/data/bears.ods")
```

```text
TBD
```

#### Scenario: Numbers
- **WHEN** an .ods sheet with numeric cells is read
- **THEN** those columns are Float64
