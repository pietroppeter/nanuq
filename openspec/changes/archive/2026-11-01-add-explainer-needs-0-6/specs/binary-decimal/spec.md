# Spec Delta

## ADDED Requirements

### Requirement: Binary slicing and bytes
The `bin` namespace SHALL provide `slice(offset, length)`, `head(n)`, `tail(n)` (negative values count from the end) and `get(index, nullOnOob = false)`, which gives the byte as UInt8; `index` MAY be an expression. Reading a single Binary cell as `string` SHALL give its raw bytes, zero bytes included.

```nim
let df = newDataFrame(series("m", @["\x03\x04\x10\x11", "ab"], Binary))
echo df.select(col("m").bin.get(1).alias("second"),
               col("m").bin.slice(2, 2).bin.encode(BinaryEncoding.Hex).alias("tail_hex"))
```

```text
TBD
```

#### Scenario: Out of bounds
- **WHEN** `bin.get(9, nullOnOob = true)` reads a 4-byte value
- **THEN** the result is null

### Requirement: Strings to integers
`str.toInteger(base = 10, dtype = Int64, strict = true)` SHALL parse strings as integers in `base` (2 to 36, or a column of bases); with `strict = false`, values that do not parse SHALL be null instead of raising.

```nim
let df = newDataFrame(series("k", @["zz", "10", "?"]))
echo df.select(col("k").str.toInteger(base = 36, strict = false))
```

```text
TBD
```

#### Scenario: Strict
- **WHEN** a value does not parse and `strict` is true
- **THEN** a `PolarsError` is raised
