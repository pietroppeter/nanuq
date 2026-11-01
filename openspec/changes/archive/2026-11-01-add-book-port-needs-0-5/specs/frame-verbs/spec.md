## ADDED Requirements

### Requirement: Frame interpolation
DataFrame and LazyFrame SHALL support `interpolate(how = InterpolationMethod.Linear)`,
filling the nulls of every column as `Expr.interpolate` does (Python's
`DataFrame.interpolate`).

```nim
let df = newDataFrame:
  day: [1, 2, 3]
  temp: [some(-2.0), none(float), some(1.0)]
echo df.interpolate
```

```text
```

#### Scenario: Integer column
- **WHEN** an integer column with a null between 1 and 5 is interpolated
- **THEN** it becomes a float column holding 1.0, 3.0, 5.0

### Requirement: Casting by data type
DataFrame and LazyFrame `cast` SHALL also take a mapping from data types, or from
selectors, to data types: `cast({Float64: Float32})` casts every Float64 column,
`cast({col(SomeNumber): Float32})` every column the selector picks; other columns are
kept.

```nim
let df = newDataFrame:
  kg: [410.5, 380.0]
  cubs: [1, 0]
  bear: ["Ada", "Bo"]
echo df.cast({Float64: Float32}).schema
echo df.cast({col(SomeNumber): Float32}).schema
```

```text
```

#### Scenario: Other columns kept
- **WHEN** `cast({Float64: Float32})` runs on a frame with an Int64 column
- **THEN** the Int64 column is unchanged
