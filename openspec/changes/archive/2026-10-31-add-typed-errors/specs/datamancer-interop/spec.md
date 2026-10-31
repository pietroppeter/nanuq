# Spec Delta

## MODIFIED Requirements

### Requirement: From Datamancer
`fromDatamancer` SHALL copy every column back in order: `int` to i64, `float` to f64,
`bool` to bool, `string` to str, constant columns repeated, and object columns of one
value kind plus nulls to that dtype with nulls. Other object columns SHALL raise
`PolarsError`.

```nim
import nanuq/datamancer
let back = penguins().toDatamancer.fromDatamancer
echo back.shape, " ", back.nullCount("body_mass_g")
```

```text
(344, 8) 2
```

#### Scenario: Round trip
- **WHEN** a Nanuq DataFrame is converted with `toDatamancer` and back with `fromDatamancer`
- **THEN** it has the same shape, columns, dtypes (for i64, f64, bool, str) and null counts

#### Scenario: Mixed object column
- **WHEN** a Datamancer object column holds both an int and a string
- **THEN** `fromDatamancer` raises `PolarsError` naming the column
