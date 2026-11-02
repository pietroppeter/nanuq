# Spec Delta

## ADDED Requirements

### Requirement: Binary functions on a Series
`s.bin` SHALL give the `bin` namespace on a Series, as on an expression.

```nim
let s = newDataFrame(series("b", @["ab", "c"])).select(col("b").cast(Binary)).getColumn("b")
echo s.bin.size
```

```text
TBD
```

#### Scenario: Same as the expression
- **WHEN** `s.bin.size` runs
- **THEN** it equals `s.eval(col(s.name).bin.size)`
