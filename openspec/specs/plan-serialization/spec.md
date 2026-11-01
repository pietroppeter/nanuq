# plan-serialization Specification

## Purpose
Saving and loading query plans and expressions (binary or JSON), and inspecting expressions with the `meta` namespace.

## Requirements

### Requirement: Serializing query plans
`lf.serialize(format = SerializationFormat.Binary)` SHALL return the LazyFrame's plan as
bytes (in a string), `Json` as JSON text, and `lf.serialize(path, format)` SHALL write it
to a file. `deserialize(LazyFrame, data, format)` and `deserializeFile(LazyFrame, path,
format)` SHALL rebuild a LazyFrame that collects to the same result. In-memory frames in
the plan SHALL travel with it.

```nim
let lf = newDataFrame(series("kg", @[410, 380, 455])).lazy.filter(col("kg") > 400)
let bytes = lf.serialize
echo deserialize(LazyFrame, bytes).collect
echo lf.serialize(SerializationFormat.Json).len > 0
```

```text
shape: (2, 1)
┌─────┐
│ kg  │
│ --- │
│ i64 │
╞═════╡
│ 410 │
│ 455 │
└─────┘
true
```

#### Scenario: Not a plan
- **WHEN** `deserialize(LazyFrame, "garbage")` is called
- **THEN** `PolarsError` is raised

#### Scenario: Nim callbacks
- **WHEN** a plan with `mapElements` is serialized
- **THEN** `PolarsError` is raised

### Requirement: Serializing expressions
`e.meta.serialize(format)` SHALL return an expression as bytes or JSON, and
`deserialize(Expr, data, format)` SHALL rebuild it.

```nim
let e = (col("kg") * 2).alias("double")
let back = deserialize(Expr, e.meta.serialize)
echo back.meta.eq(e)
echo newDataFrame(series("kg", @[1, 2])).select(back)
```

```text
true
shape: (2, 1)
┌────────┐
│ double │
│ ---    │
│ i64    │
╞════════╡
│ 2      │
│ 4      │
└────────┘
```

#### Scenario: JSON round trip
- **WHEN** an expression is serialized with `Json` and deserialized with `Json`
- **THEN** `meta.eq` with the original is true

### Requirement: Expression metadata
The `meta` namespace SHALL also provide `eq(other)` and `ne(other)` (same expression
tree), `pop` (the inputs of the outermost node), `isRegexProjection`,
`isColumnSelection(allowAliasing = false)`, `isLiteral(allowAliasing)` and `treeFormat`
(the tree as text).

```nim
let e = (col("a") + col("b")).alias("c")
echo e.meta.undoAliases.meta.outputName
echo e.meta.pop.len
echo col("^x.*$").meta.isRegexProjection, " ", col("a").alias("b").meta.isColumnSelection(allowAliasing = true)
echo (col("a") + 1).meta.treeFormat
```

```text
a
1
true true
               0               1
   ┌─────────────────────────────────
   │
   │     ╭───────────╮
 0 │     │ binary: + │
   │     ╰─────┬┬────╯
   │           ││
   │           │╰──────────────╮
   │           │               │
   │  ╭────────┴────────╮  ╭───┴────╮
 1 │  │ lit(dyn int: 1) │  │ col(a) │
   │  ╰─────────────────╯  ╰────────╯
```

#### Scenario: Different trees
- **WHEN** `col("a").meta.eq(col("b"))` is called
- **THEN** it is false
