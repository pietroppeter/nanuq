# arrow-interop Specification

## Purpose
Exchanging columns and frames with other libraries through the Arrow C Data Interface, and zero-copy access to numeric columns from Nim.

## Requirements

### Requirement: Series through the Arrow C Data Interface
`s.toArrow` SHALL export a Series as an `ArrowExport` holding the standard
`ArrowSchema` and `ArrowArray` C structs, without copying the values. Whatever a consumer
did not take over SHALL be released when the export goes away. `fromArrow(schema, array,
name = "")` SHALL import a Series from such structs, taking over the array.

```nim
var ex = series("kg", @[410, 380]).toArrow
echo ex.schema.format, " ", ex.array.length
let back = fromArrow(ex, name = "mass")
echo back
```

```text
l 2
shape: (2,)
Series: 'mass' [i64]
[
	410
	380
]
```

#### Scenario: Taken over
- **WHEN** an export's array is imported with `fromArrow`
- **THEN** the export's `array.release` is nil and the Series reads the same values

### Requirement: Frames through the Arrow C stream interface
`df.toArrow` SHALL export a frame as an `ArrowArrayStream` of record batches (struct
arrays), and `fromArrow(stream)` SHALL read a whole stream into a frame and release it.

```nim
let df = newDataFrame(series("bear", @["Ada", "Bo"]), series("kg", @[410.0, 380.5]))
var stream = df.toArrow
echo fromArrow(stream)
```

```text
shape: (2, 2)
┌──────┬───────┐
│ bear ┆ kg    │
│ ---  ┆ ---   │
│ str  ┆ f64   │
╞══════╪═══════╡
│ Ada  ┆ 410.0 │
│ Bo   ┆ 380.5 │
└──────┴───────┘
```

#### Scenario: Nested and temporal columns
- **WHEN** a frame with List, Struct and Datetime columns goes through `toArrow` and `fromArrow`
- **THEN** the result equals the frame

### Requirement: Zero-copy views
`s.view(T)` and `df.view(column, T)` SHALL give a `ColumnView[T]` over a numeric column's
values without copying, with `[]`, `len`, `items` and `toOpenArray`. `T` SHALL match the
column's type exactly and the column SHALL have no nulls, else `InvalidOperationError`.

```nim
import std/math
let df = newDataFrame(series("kg", @[410.0, 380.5, 455.0]))
let v = df.view("kg", float)
echo v.len, " ", v[1], " ", sum(v.toOpenArray)
```

```text
3 380.5 1245.5
```

#### Scenario: Wrong type
- **WHEN** an Int64 column is viewed as `float`
- **THEN** `InvalidOperationError` is raised

#### Scenario: Nulls
- **WHEN** a column with a null is viewed
- **THEN** `InvalidOperationError` is raised
