## ADDED Requirements

### Requirement: Series namespaces
A Series SHALL have the namespaces `list`, `arr`, `struct`, `str`, `dt` and `cat`, each
offering every function of the Expr namespace of the same name: `s.ns.f(args)` SHALL
return the Series `s.eval(col(s.name).ns.f(args))`. The result keeps the name the
expression gives (so `s.struct.field("x")` is named `x`).

```nim
let df = newDataFrame:
  p: [(x: 1, y: 2.0), (x: 3, y: 4.0)]
  l: [@[1, 2], @[3]]
echo df["p"].struct.field("x")
echo df["l"].list.len
```

```text
```

#### Scenario: String function on a Series
- **WHEN** `s.str.toUppercase` runs on a String Series holding "ab" and "c"
- **THEN** the result holds "AB" and "C"

### Requirement: Series as HTML
`toHtml(s: Series, maxRows = 10)` SHALL return the HTML that Python Polars shows for a
Series in notebooks: the table of its one column, with the shape written `(n,)`.

```nim
let s = series("kg", [410, 380])
echo s.toHtml
```

```text
```

#### Scenario: Shape of a Series
- **WHEN** a Series of 3 values is turned into HTML
- **THEN** the HTML shows `shape: (3,)`

### Requirement: Columns from sized numbers
`series`, `newDataFrame`, lists and arrays SHALL accept `int8`, `int16`, `int32`,
`int64`, `uint8`, `uint16`, `uint32`, `uint64` and `float32` values (and `Option` of
them), giving the Polars type of the same size, and `toList` SHALL read columns back as
those types.

```nim
let df = newDataFrame:
  rgb: [[255'u8, 0, 0], [0'u8, 128, 255]]
  temp: [-1.5'f32, 2.0]
echo df
echo df.toList("temp", float32)
```

```text
```

#### Scenario: Int32 column
- **WHEN** `series("a", [1'i32, 2])` is built
- **THEN** its data type is Int32 and `toList(int32)` gives `@[1'i32, 2]`
