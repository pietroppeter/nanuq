## MODIFIED Requirements

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
```

#### Scenario: Schema of nested columns
- **WHEN** the schema of a frame with a list of strings column is read
- **THEN** its dtype is `List(String)` and `$` gives `List(String)`

#### Scenario: Struct field types
- **WHEN** `fields` is read from the dtype of a struct column built from `(x: 1, y: 2.0)`
- **THEN** it holds `x: Int64` and `y: Float64`, in order
