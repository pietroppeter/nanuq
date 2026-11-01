# Spec Delta

## ADDED Requirements

### Requirement: Full-range UInt64
UInt64 columns SHALL keep all 64 bits between Nim and Polars: `series(name, seq[uint64])` (with or without `Option`) and `toList(uint64)` SHALL handle values above `high(int64)`.

```nim
let df = newDataFrame(series("key", @[1'u64, 9223372036854775809'u64]))
echo df.toList("key", uint64)
echo df.select(col("key").bitwiseXor)
```

```text
TBD
```

#### Scenario: Nulls
- **WHEN** `series("u", [some(x), none(uint64)])` is built
- **THEN** the second value is null
