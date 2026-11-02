# Proposal

## Why

Binary and Decimal are the two Polars data types Nanuq still shows as `Other`. Decimal
matters for money and for data read from databases and Parquet files that store exact
numbers; Binary for raw bytes (hashes, images, encoded payloads) and is the one blocker
of the user guide's lazy/gpu page. Bitwise operations come with them in the roadmap's
0.6 line "Binary, Decimal dtypes; bitwise ops". It takes the BACKLOG.md entry "More
dtypes".

It is the third change of the 0.6 release.

## What Changes

- `DataTypeKind` gains `Binary` and `Decimal`; constants `Binary` and
  `Decimal(precision = 38, scale = 0)`; tables print `binary` and `decimal[p,s]`, `$`
  prints `Binary` and `Decimal(p, s)`.
- `series(name, strings, dtype)`: with `Binary` the strings are raw bytes (any bytes);
  other dtypes cast the strings (`Decimal(5, 2)` parses them).
- Reading back: Binary columns read as `string` (raw bytes); Decimal columns as
  `string` (exact) or `float`.
- `bin` namespace: `contains`, `startsWith`, `endsWith`, `encode(Hex | Base64)`,
  `decode(Hex | Base64)`, `size(unit)`.
- `str.encode(Hex | Base64)`, `str.toDecimal(scale)`.
- Bitwise expressions: `bitwiseCountOnes`, `bitwiseCountZeros`, `bitwiseLeadingOnes`,
  `bitwiseLeadingZeros`, `bitwiseTrailingOnes`, `bitwiseTrailingZeros`, and the
  aggregations `bitwiseAnd`, `bitwiseOr`, `bitwiseXor`. (`and`, `or`, `xor` between
  integer expressions already work bitwise, as in Polars.)

## Capabilities

### New Capabilities
- `binary-decimal`: Binary and Decimal data and their functions, bitwise operations.

## Differences from Polars

- Nim has no `bytes` type: Binary values are Nim strings holding raw bytes, built with
  `series(name, strings, Binary)` (Python `pl.Series([b"..."])`).
- Nim has no decimal type in the standard library: Decimal values are read as strings
  (exact) or floats, and written from strings (Python uses `decimal.Decimal`).
- `encode`/`decode` take a `BinaryEncoding` enum (Python `"hex"`/`"base64"` strings);
  `decode` is always strict.
- `str.toDecimal` takes the `scale`; Python 2.x infers it from the first rows
  (`inference_length`).

## Impact

- `src/rust/Cargo.toml`: Polars features `binary_encoding`, `bitwise`, `string_encoding`.
- `src/rust/src/lib.rs`, `src/nanuq/ffi.nim`: dtype codes, `nq_dtype_decimal`,
  `nq_series_new_binary`, `nq_expr_bin`, `nq_expr_str_codec`, `nq_expr_bitwise`;
  string reads accept Binary columns, float reads Decimal ones.
- New `tests/test_binary_decimal.nim`.
