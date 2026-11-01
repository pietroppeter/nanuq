# Proposal

## Why

`$` on a `DataType` printed Polars' short names (`i64`, `list[str]`, `struct[2]`), the
names in table headers. Reviewing the "Designing Nanuq 0.5" post, Pietro asked why.
Python prints data types differently (`Int64`, `List(String)`,
`Struct({'x': Int64})`), and the short names hide struct fields and are not what you
write in Nim. Pietro chose (2026-11-01): print a data type as the Nanuq code that builds
it.

It is the tenth change of the 0.5 release (#53).

## What Changes

- **BREAKING** `$DataType` gives Nanuq code: `Int64`, `String`, `Categorical`,
  `List(String)`, `Array(Float64, 3)`, `Array(Int64, [2, 3])`,
  `Struct({"x": Int64, "y": Float64})`, `Enum(["low", "high"])`; temporal types print
  as the Nim types they cast to: `Date`, `TimeOfDay`,
  `DateTime(Milliseconds, "Europe/Rome")`, `Duration(Microseconds)`. Schemas print with
  it too (`{"a": Int64}`).
- Table headers, `glimpse` and `toHtml` keep Polars' short names, as Polars prints them.

## Capabilities

### Modified Capabilities
- `data-types`: how data types print.
- `nested-data`: how nested data types print.

## Differences from Polars

- Python prints `Array(Float64, shape=(3,))`, `Struct({'x': Int64})` (single quotes),
  `Datetime(time_unit='ms', time_zone='Europe/Rome')`, `Time` and
  `Enum(categories=['low', 'high'])`; Nanuq prints its own spelling of the same types.
- Rust Polars' `Display` (and so the table headers) uses the short names.

## Impact

- `src/nanuq.nim`: new `$` for `DataType`; the old one becomes the internal
  `shortName`, used by `toHtml` and `glimpse`.
- Spec example outputs, tests that compare `$dtype`, dev-log section 1.
