# series Specification

## Purpose
Single columns as Series: getting them from frames, reading them, operating on them through the expression methods of the same name, and putting them back into frames.

## Requirements

### Requirement: Getting a Series
`df["name"]` and `df.getColumn("name")` SHALL return the column as a Series, and
`df.toSeries(index = 0)` the column at a position (negative from the end); a missing
column SHALL raise `ColumnNotFoundError`. A Series SHALL have `name`, `len`, `dtype`,
`nullCount` and `$`, which shows Polars' Series display.

```nim
let df = newDataFrame:
  year: [1997, 2015, 2023]
  oni: [2.4, 2.6, 2.0]
let s = df["oni"]
echo s
echo s.name, " ", s.len, " ", s.dtype
```

```text
shape: (3,)
Series: 'oni' [f64]
[
	2.4
	2.6
	2.0
]
oni 3 Float64
```

#### Scenario: Missing column
- **WHEN** `df["nope"]` runs on a frame without that column
- **THEN** `ColumnNotFoundError` is raised

### Requirement: Reading a Series
`s.toList(T)` and `s.toList(Option[T])` SHALL return the values, `s[i, T]` one value,
and `s.item(T)` the only value of a one-value Series (raising `InvalidOperationError`
otherwise). `toFrame` SHALL return a one-column frame, and `alias`/`rename` and
`cast` SHALL return a renamed or converted Series.

```nim
let s = series("oni", [2.4, 2.6, 2.0])
echo s.toList(float), " ", s[1, float]
echo s.toFrame.columns
```

```text
@[2.4, 2.6, 2.0] 2.6
@["oni"]
```

#### Scenario: item on a longer Series
- **WHEN** `item(float)` is called on a Series of three values
- **THEN** `InvalidOperationError` is raised

### Requirement: Series operations
Series SHALL support the arithmetic, comparison and boolean operators with literals and
other Series of the same length, `filter(mask)`, and the expression methods that take no
other column (aggregations, math, cumulative, rolling, ranking, distinct values,
recoding, binning), each SHALL give the same values as the expression of the same name
on a one-column frame. Aggregations SHALL return a Series of one value.

```nim
let s = series("oni", [0.5, -1.0, 2.0, 1.2])
echo s.max.item(float)
echo ((s - s.mean.item(float)) / s.std.item(float)).round(2).toList(float)
echo s.filter(s > 0.5).toList(float)
echo s.rollingMean(2).toList(Option[float])
```

```text
2.0
@[-0.14, -1.31, 1.04, 0.41]
@[2.0, 1.2]
@[none(float), some(-0.25), some(0.5), some(1.6)]
```

#### Scenario: Two Series
- **WHEN** `a + b` runs on Series a = 1, 2 and b = 10, 20
- **THEN** the result is 11, 22 named like `a`

### Requirement: Series in frames
`df.withColumns(series...)` SHALL add or replace columns with Series of the frame's
height, and `lit(series)` SHALL use a Series as a column in an expression.

```nim
let df = newDataFrame:
  year: [1997, 2015, 2023]
let peak = series("peak", [2.4, 2.6, 2.0])
echo df.withColumns(peak, (peak * 10).alias("tenths"))
```

```text
shape: (3, 3)
┌──────┬──────┬────────┐
│ year ┆ peak ┆ tenths │
│ ---  ┆ ---  ┆ ---    │
│ i64  ┆ f64  ┆ f64    │
╞══════╪══════╪════════╡
│ 1997 ┆ 2.4  ┆ 24.0   │
│ 2015 ┆ 2.6  ┆ 26.0   │
│ 2023 ┆ 2.0  ┆ 20.0   │
└──────┴──────┴────────┘
```

#### Scenario: Expression with a Series
- **WHEN** `select(col.year + lit(series("d", [1, 1, 1])))` runs
- **THEN** each year grows by one

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
shape: (2,)
Series: 'x' [i64]
[
	1
	3
]
shape: (2,)
Series: 'l' [u32]
[
	2
	1
]
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
<div><style>
.dataframe > thead > tr,
.dataframe > tbody > tr {
  text-align: right;
  white-space: pre-wrap;
}
</style>
<small>shape: (2,)</small><table border="1" class="dataframe"><thead><tr><th>kg</th></tr><tr><td>i64</td></tr></thead><tbody><tr><td>410</td></tr><tr><td>380</td></tr></tbody></table></div>
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
shape: (2, 2)
┌───────────────┬──────┐
│ rgb           ┆ temp │
│ ---           ┆ ---  │
│ array[u8, 3]  ┆ f32  │
╞═══════════════╪══════╡
│ [255, 0, 0]   ┆ -1.5 │
│ [0, 128, 255] ┆ 2.0  │
└───────────────┴──────┘
@[-1.5, 2.0]
```

#### Scenario: Int32 column
- **WHEN** `series("a", [1'i32, 2])` is built
- **THEN** its data type is Int32 and `toList(int32)` gives `@[1'i32, 2]`
