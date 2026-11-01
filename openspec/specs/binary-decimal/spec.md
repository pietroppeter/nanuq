# binary-decimal Specification

## Purpose
Binary (raw bytes) and Decimal (exact) columns, the `bin` namespace, string encodings and bitwise expressions.

## Requirements

### Requirement: Binary data
`Binary` SHALL be a data type of raw bytes. `series(name, strings, Binary)` SHALL build a
Binary column whose values are the strings' bytes (any bytes), and `toList(column,
string)` SHALL read them back unchanged.

```nim
let s = series("sig", ["\x00\xff", "bear"], Binary)
echo s.dtype
let df = newDataFrame(s)
echo df
echo df.toList("sig", string) == @["\x00\xff", "bear"]
```

```text
Binary
shape: (2, 1)
┌─────────────┐
│ sig         │
│ ---         │
│ binary      │
╞═════════════╡
│ b"\x00\xff" │
│ b"bear"     │
└─────────────┘
true
```

#### Scenario: Cast from strings
- **WHEN** a String column is cast to `Binary`
- **THEN** its values read back as the same strings

### Requirement: Decimal data
`Decimal(precision = 38, scale = 0)` SHALL be the exact decimal type, with precision 1 to
38 and scale 0 to precision (else `ValueError`). Strings SHALL become decimals with
`series(name, strings, Decimal(p, s))` or `str.toDecimal(scale)`, and Decimal columns
SHALL read back as `string` (exact) or `float`.

```nim
let df = newDataFrame(series("price", ["1.25", "10.50", "0.10"], Decimal(10, 2)))
echo df
echo df.select(col("price").sum)
echo df.toList("price", float)
```

```text
shape: (3, 1)
┌───────────────┐
│ price         │
│ ---           │
│ decimal[10,2] │
╞═══════════════╡
│ 1.25          │
│ 10.50         │
│ 0.10          │
└───────────────┘
shape: (1, 1)
┌───────────────┐
│ price         │
│ ---           │
│ decimal[38,2] │
╞═══════════════╡
│ 11.85         │
└───────────────┘
@[1.25, 10.5, 0.1]
```

#### Scenario: Bad precision
- **WHEN** `Decimal(40, 2)` is called
- **THEN** `ValueError` is raised

### Requirement: Binary functions
`e.bin` SHALL provide `contains`, `startsWith`, `endsWith` (with a string of bytes or an
expression), `encode(BinaryEncoding)` (hex or base64 text), `decode(BinaryEncoding)` and
`size(unit = SizeUnit.Bytes)`; `str.encode(BinaryEncoding)` SHALL encode strings' UTF-8
bytes.

```nim
let df = newDataFrame(series("b", ["bear", "cub"], Binary))
echo df.select(col("b").bin.encode(BinaryEncoding.Hex).alias("hex"),
               col("b").bin.startsWith("be").alias("be"), col("b").bin.size.alias("n"))
echo newDataFrame(series("s", @["hi"])).select(col("s").str.encode(BinaryEncoding.Base64))
```

```text
shape: (2, 3)
┌──────────┬───────┬─────┐
│ hex      ┆ be    ┆ n   │
│ ---      ┆ ---   ┆ --- │
│ str      ┆ bool  ┆ u32 │
╞══════════╪═══════╪═════╡
│ 62656172 ┆ true  ┆ 4   │
│ 637562   ┆ false ┆ 3   │
└──────────┴───────┴─────┘
shape: (1, 1)
┌──────┐
│ s    │
│ ---  │
│ str  │
╞══════╡
│ aGk= │
└──────┘
```

#### Scenario: Round trip
- **WHEN** a Binary column is encoded to hex, cast to Binary and decoded from hex
- **THEN** the values equal the original

### Requirement: Bitwise operations
Integer expressions SHALL provide `bitwiseCountOnes`, `bitwiseCountZeros`,
`bitwiseLeadingOnes`, `bitwiseLeadingZeros`, `bitwiseTrailingOnes`,
`bitwiseTrailingZeros` (per value) and `bitwiseAnd`, `bitwiseOr`, `bitwiseXor`
(aggregations).

```nim
let df = newDataFrame(series("flags", @[0b0110'u8, 0b0011'u8]))
echo df.select(col("flags").bitwiseCountOnes.alias("ones"),
               col("flags").bitwiseTrailingZeros.alias("tz"))
echo df.select(col("flags").bitwiseAnd.alias("and"), col("flags").bitwiseOr.alias("or"))
```

```text
shape: (2, 2)
┌──────┬─────┐
│ ones ┆ tz  │
│ ---  ┆ --- │
│ u32  ┆ u32 │
╞══════╪═════╡
│ 2    ┆ 1   │
│ 2    ┆ 0   │
└──────┴─────┘
shape: (1, 2)
┌─────┬─────┐
│ and ┆ or  │
│ --- ┆ --- │
│ u8  ┆ u8  │
╞═════╪═════╡
│ 2   ┆ 7   │
└─────┴─────┘
```

#### Scenario: Not integers
- **WHEN** `bitwiseCountOnes` is applied to a String column
- **THEN** `PolarsError` is raised

### Requirement: Binary slicing and bytes
The `bin` namespace SHALL provide `slice(offset, length)`, `head(n)`, `tail(n)` (negative values count from the end) and `get(index, nullOnOob = false)`, which gives the byte as UInt8; `index` MAY be an expression. Reading a single Binary cell as `string` SHALL give its raw bytes, zero bytes included.

```nim
let df = newDataFrame(series("m", @["\x03\x04\x10\x11", "ab"], Binary))
echo df.select(col("m").bin.get(1).alias("second"),
               col("m").bin.slice(2, 2).bin.encode(BinaryEncoding.Hex).alias("tail_hex"))
```

```text
shape: (2, 2)
┌────────┬──────────┐
│ second ┆ tail_hex │
│ ---    ┆ ---      │
│ u8     ┆ str      │
╞════════╪══════════╡
│ 4      ┆ 1011     │
│ 98     ┆          │
└────────┴──────────┘
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
shape: (3, 1)
┌──────┐
│ k    │
│ ---  │
│ i64  │
╞══════╡
│ 1295 │
│ 36   │
│ null │
└──────┘
```

#### Scenario: Strict
- **WHEN** a value does not parse and `strict` is true
- **THEN** a `PolarsError` is raised
