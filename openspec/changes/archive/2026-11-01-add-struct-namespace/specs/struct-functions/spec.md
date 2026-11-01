# Spec Delta

## ADDED Requirements

### Requirement: Building structs
`asStruct(exprs)` SHALL build a struct column with one field per expression, named after
its output name.

```nim
let df = newDataFrame:
  bear: ["Ada", "Bo"]
  kg: [410, 380]
echo df.select(asStruct(col("bear"), col("kg") * 2).alias("s"))
```

```text
TBD
```

#### Scenario: Duplicate names
- **WHEN** two expressions with the same output name are put in one struct
- **THEN** `DuplicateError` is raised

### Requirement: Struct fields
`e.struct.field(name)` (also `e.struct[name]`) SHALL give one field as a column,
`field(names)` several, `field(index)` one by position, and `e.struct.unnest` all of
them; `renameFields(names)` SHALL rename the fields in order, `withFields(exprs)` add or
replace fields, and `jsonEncode` give each struct as a JSON string.

```nim
let df = newDataFrame:
  p: [(x: 1, y: 2.0), (x: 3, y: 4.0)]
echo df.select(col("p").struct.field("x"), col("p").struct["y"].alias("y"),
               col("p").struct.jsonEncode.alias("json"))
echo df.select(col("p").struct.renameFields(["a", "b"]).struct.unnest)
```

```text
TBD
```

#### Scenario: Unknown field
- **WHEN** `struct.field("z")` is evaluated on a struct without `z`
- **THEN** `StructFieldNotFoundError` is raised

### Requirement: Unnesting frames
`df.unnest(columns)` SHALL replace each struct column by its fields (eager and lazy);
with `separator`, the new columns SHALL be named `<column><separator><field>`.

```nim
let df = newDataFrame:
  bear: ["Ada", "Bo"]
  den: [(lat: 78.2, lon: 15.6), (lat: 79.0, lon: 16.1)]
echo df.unnest("den")
echo df.unnest("den", separator = "_").columns
```

```text
TBD
```

#### Scenario: Not a struct
- **WHEN** a list column is unnested
- **THEN** `InvalidOperationError` or `SchemaError` is raised

### Requirement: Value counts as an expression
`e.valueCounts(sort, parallel, name, normalize)` SHALL give a struct column with the
distinct values and their counts (or fractions with `normalize`), named `count` (or
`proportion`) unless `name` is given.

```nim
let df = newDataFrame:
  island: ["Biscoe", "Dream", "Biscoe"]
echo df.select(col("island").valueCounts(sort = true)).unnest("island")
```

```text
TBD
```

#### Scenario: Sorted counts
- **WHEN** `valueCounts(sort = true)` is evaluated
- **THEN** the most frequent value comes first

### Requirement: Array functions
`e.arr` SHALL give a namespace of functions on each array of an Array column: `len`,
`sum`, `min`, `max`, `mean`, `median`, `std`, `var`, `argMin`, `argMax`, `first`,
`last`, `get`, `join`, `contains`, `countMatches`, `sort`, `slice`, `head`, `tail`,
`shift`, `toList`, `toStruct`, `explode`, `eval` and `agg`.

```nim
let df = newDataFrame:
  rgb: [[255, 0, 0], [10, 20, 30]]
echo df.select(col("rgb").arr.sum.alias("sum"), col("rgb").arr.get(1).alias("g"),
               col("rgb").arr.toList.alias("list"))
```

```text
TBD
```

#### Scenario: Array to struct
- **WHEN** `arr.toStruct` is evaluated on arrays of width 3
- **THEN** the result is a struct with fields `field_0`, `field_1` and `field_2`
