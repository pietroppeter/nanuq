# nested-data Specification

## Purpose
List, Array and Struct data types, and nested values between Nim and Polars.

## Requirements

### Requirement: Nested data types
`DataType` SHALL have the kinds `List`, `Array` and `Struct`, built by `List(inner)`,
`Array(inner, width)` (or a shape, `Array(Int64, [2, 3])`) and `Struct(fields)` (from
`{"name": dtype}` pairs or a seq of `Field`). `inner`, `width`, `shape` and `fields` SHALL
read them back, `$` SHALL print the constructor call (`List(Int64)`, `Array(Int64, [2, 3])`,
`Struct({"x": Float64})`) and `==` SHALL compare the whole type.

```nim
let point = Struct({"x": Float64, "y": Float64})
echo List(Int64), " ", Array(Float64, 3), " ", Array(Int64, [2, 3]), " ", point
echo List(point).inner == point, " ", Array(Int64, [2, 3]).shape, " ", point.fields[1].name
```

```text
List(Int64) Array(Float64, 3) Array(Int64, [2, 3]) Struct({"x": Float64, "y": Float64})
true @[2, 3] y
```

#### Scenario: Schema of nested columns
- **WHEN** the schema of a frame with a list of strings column is read
- **THEN** its dtype is `List(String)` and `$` gives `List(String)`

#### Scenario: Struct field types
- **WHEN** `fields` is read from the dtype of a struct column built from `(x: 1, y: 2.0)`
- **THEN** it holds `x: Int64` and `y: Float64`, in order

### Requirement: Nested columns from Nim
`series(name, values)` SHALL build a List column from seqs, an Array column from Nim
arrays, and a Struct column from objects or named tuples, at any depth (seqs of objects,
objects with seq fields). `Option` values SHALL be null rows, and `Option` elements null
values inside a list. The `newDataFrame` block and `toDataFrame(rows)` SHALL take the
same values; in the block `nil` SHALL be a null row. `lit(seq)` SHALL be a list literal.

```nim
let df = newDataFrame:
  tags: [@["polar", "bear"], @[], nil]
  point: [(x: 1, y: 2.0), (x: 3, y: 4.0), (x: 5, y: 6.0)]
  rgb: [[255, 0, 0], [0, 255, 0], [0, 0, 255]]
echo df
echo df.select(lit(@[1, 2]).alias("lit"))
```

```text
shape: (3, 3)
┌───────────────────┬───────────┬───────────────┐
│ tags              ┆ point     ┆ rgb           │
│ ---               ┆ ---       ┆ ---           │
│ list[str]         ┆ struct[2] ┆ array[i64, 3] │
╞═══════════════════╪═══════════╪═══════════════╡
│ ["polar", "bear"] ┆ {1,2.0}   ┆ [255, 0, 0]   │
│ []                ┆ {3,4.0}   ┆ [0, 255, 0]   │
│ null              ┆ {5,6.0}   ┆ [0, 0, 255]   │
└───────────────────┴───────────┴───────────────┘
shape: (1, 1)
┌───────────┐
│ lit       │
│ ---       │
│ list[i64] │
╞═══════════╡
│ [1, 2]    │
└───────────┘
```

#### Scenario: Empty lists keep their type
- **WHEN** `series("a", newSeq[seq[int]](2))` is built
- **THEN** its dtype is `List(Int64)` and both values are empty lists

#### Scenario: Null values inside a list
- **WHEN** `series("a", @[@[some(1), none(int)]])` is built
- **THEN** the list holds 1 and null

### Requirement: Nested values to Nim
`toList(column, T)` SHALL read a List column as `seq[U]`, an Array column as `array[N, U]`
or `seq[U]`, and a Struct column as an object or named tuple matching fields by name, on
frames and Series, at any depth; `Option[T]` SHALL read null rows as `none`. Cell reads
`df[column, row, T]` and `rows(T)` SHALL take the same types. A null read into a plain
type SHALL raise `InvalidOperationError`, and an object field without a struct field
`ColumnNotFoundError`.

```nim
type Point = object
  x: int
  y: float
let df = newDataFrame:
  tags: [@["polar", "bear"], @[]]
  point: [Point(x: 1, y: 2.0), Point(x: 3, y: 4.0)]
echo df.toList("tags", seq[string])
echo df.toList("point", Point)
echo df["point", 1, tuple[x: int]]
for r in df.rows(tuple[tags: seq[string], point: Point]):
  echo r.tags.len, " ", r.point.y
```

```text
@[@["polar", "bear"], @[]]
@[(x: 1, y: 2.0), (x: 3, y: 4.0)]
(x: 3)
2 2.0
0 4.0
```

#### Scenario: Round trip
- **WHEN** a seq of objects with seq and object fields is turned into a frame and read back with `rows`
- **THEN** the result equals the original seq

#### Scenario: Null row
- **WHEN** a list column with a null row is read as `seq[int]` rows
- **THEN** `InvalidOperationError` is raised; read as `Option[seq[int]]` it gives `none`

### Requirement: Casting to nested types
`cast(dtype)` and `castTo` SHALL accept nested data types, and `cast(T)` nested Nim types.

```nim
let df = newDataFrame(series("a", @[@[1, 2], @[3]]))
echo df.select(col("a").cast(List(Float64)), col("a").cast(seq[string]).alias("s"))
```

```text
shape: (2, 2)
┌────────────┬────────────┐
│ a          ┆ s          │
│ ---        ┆ ---        │
│ list[f64]  ┆ list[str]  │
╞════════════╪════════════╡
│ [1.0, 2.0] ┆ ["1", "2"] │
│ [3.0]      ┆ ["3"]      │
└────────────┴────────────┘
```

#### Scenario: List to array
- **WHEN** a list column whose lists all have 2 values is cast to `Array(Int64, 2)`
- **THEN** the result is an array column
