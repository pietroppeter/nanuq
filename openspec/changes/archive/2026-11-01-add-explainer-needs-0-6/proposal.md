# Proposal

## Why

The 0.6 explainer ("Move 37", go games) stores moves as Binary values, hashes board
positions with 64-bit Zobrist keys, and reads raw lines from text files. Its Python
draft (py-polars 2.1) needs a few things the first nine 0.6 changes did not cover.

It is the tenth change of the 0.6 release.

## What Changes

- `bin.slice(offset, length)`, `bin.head(n)`, `bin.tail(n)`, `bin.get(index, nullOnOob)`
  (index may be an expression); reading one Binary cell returns its raw bytes, zero
  bytes included.
- `str.toInteger(base = 10, dtype = Int64, strict = true)`, base 2 to 36 or a column.
- UInt64 values above `high(int64)`: `series("u", @[x'u64])` and `toList(uint64)` keep
  all 64 bits.
- `readCsv`/`scanCsv`: `quoteChar` (`none(char)` turns quoting off), `encoding`
  (`CsvEncoding.Utf8Lossy`) and `newColumns`.

## Capabilities

### Modified Capabilities
- `binary-decimal`: binary slicing and byte access, `str.toInteger`.
- `csv-io`: `quoteChar`, `encoding`, `newColumns`.
- `data-types`: UInt64 values above `high(int64)`.

## Differences from Polars

- `quoteChar` is an `Option[char]` (Python: `quote_char: str | None`); `encoding` is an
  enum (Python strings `"utf8"`, `"utf8-lossy"`).
- `mod` on Decimal columns is not in the Polars 0.55 crate (py-polars 2.1 has it): cast
  to Float64 first. This is part of the known version drift.
- `str.toInteger` needs the Polars Int128/UInt128 types in the crate (a Polars 0.55
  build requirement); they still read as `DataTypeKind.Other`.

## Impact

- `src/rust/src/lib.rs`: `nq_expr_bin_slice`, `nq_expr_str_to_integer`,
  `nq_series_new_u64`, `nq_df_column_u64`, CSV options; features `string_to_integer`,
  `dtype-i128`, `dtype-u128`.
- `src/nanuq.nim`, `src/nanuq/ffi.nim`; new `tests/test_explainer6.nim`.
