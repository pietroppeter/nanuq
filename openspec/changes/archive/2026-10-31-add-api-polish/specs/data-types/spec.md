# Spec Delta

## MODIFIED Requirements

### Requirement: Casting
The API SHALL cast expressions (`e.cast(target, strict = true)`), all columns of a
DataFrame or LazyFrame (`cast(target, strict = true)`), where `target` is a Nim type or
a `DataType`, and named columns (`cast({"a": Int32}, strict = true)`) with `DataType`
values. A strict cast SHALL raise `NanuqError` (when the query
runs) if a value cannot be converted; a non-strict cast SHALL turn such values into
nulls. Casting to a `DataTypeKind.Other` dtype SHALL raise `NanuqError`.

```nim
let df = newDataFrame(series("a", [1, 2]), series("s", ["1", "x"]))
echo df.cast({"a": Int32}).dtype("a")
echo df.select(col("a").cast(float32)).dtype("a")
echo df.select(col("s").cast(Int64, strict = false))
```

```text
i32
f32
shape: (2, 1)
┌──────┐
│ s    │
│ ---  │
│ i64  │
╞══════╡
│ 1    │
│ null │
└──────┘
```

#### Scenario: Narrow an integer column
- **WHEN** `df.cast({"a": Int32})` runs on an i64 column
- **THEN** `dtype("a") == Int32` and `toList(df, "a", int)` returns the same values

#### Scenario: Nim type as target
- **WHEN** `col("a").cast(float32)` is selected from an i64 column
- **THEN** the result column has dtype `Float32`

#### Scenario: Strict failure
- **WHEN** a string column holding "1" and "x" is cast to `Int64` with `strict = true`
- **THEN** `NanuqError` is raised

#### Scenario: Non-strict cast
- **WHEN** the same column is cast with `strict = false`
- **THEN** the result is 1 and null
