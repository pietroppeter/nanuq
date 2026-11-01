# math-functions Specification

## Purpose
Elementwise math on expressions: roots, exponentials and logarithms, rounding to integers, clipping, trigonometry, the dot product, and NaN and infinity, which Polars keeps apart from null.

## Requirements

### Requirement: Elementwise math
Expressions SHALL have `sqrt`, `cbrt`, `exp`, `log(base = E)`, `log10`, `log1p`,
`sign`, `floor` and `ceil`, computed value by value as in Polars, with nulls staying null.
`sqrt`, `cbrt`, `exp` and the logarithms SHALL return Float64 for integer input.

```nim
let df = newDataFrame:
  x: [1.0, 4.0, 10.0, nil]
echo df.select(col.x.sqrt.alias("sqrt"), col.x.log10.alias("log10"),
               col.x.log(2.0).alias("log2"), col.x.exp.round(1).alias("exp"))
```

```text
shape: (4, 4)
┌──────────┬─────────┬──────────┬─────────┐
│ sqrt     ┆ log10   ┆ log2     ┆ exp     │
│ ---      ┆ ---     ┆ ---      ┆ ---     │
│ f64      ┆ f64     ┆ f64      ┆ f64     │
╞══════════╪═════════╪══════════╪═════════╡
│ 1.0      ┆ 0.0     ┆ 0.0      ┆ 2.7     │
│ 2.0      ┆ 0.60206 ┆ 2.0      ┆ 54.6    │
│ 3.162278 ┆ 1.0     ┆ 3.321928 ┆ 22026.5 │
│ null     ┆ null    ┆ null     ┆ null    │
└──────────┴─────────┴──────────┴─────────┘
```

#### Scenario: Integer input
- **WHEN** `sqrt` runs on an Int64 column holding 4 and 9
- **THEN** the result is a Float64 column holding 2.0 and 3.0

#### Scenario: Sign, floor and ceil
- **WHEN** `sign`, `floor` and `ceil` run on -2.5 and 1.5
- **THEN** they give -1 and 1, -3.0 and 1.0, -2.0 and 2.0

### Requirement: Clipping
`clip(lowerBound, upperBound)` SHALL limit values to the range, and `clip(lowerBound = v)`
or `clip(upperBound = v)` SHALL limit them on one side. Bounds SHALL be literals or
expressions.

```nim
let df = newDataFrame:
  anomaly: [-2.1, -0.3, 0.4, 2.6]
echo df.select(col.anomaly.clip(-1.0, 1.0).alias("both"),
               col.anomaly.clip(lowerBound = 0.0).alias("warm_only"))
```

```text
shape: (4, 2)
┌──────┬───────────┐
│ both ┆ warm_only │
│ ---  ┆ ---       │
│ f64  ┆ f64       │
╞══════╪═══════════╡
│ -1.0 ┆ 0.0       │
│ -0.3 ┆ 0.0       │
│ 0.4  ┆ 0.4       │
│ 1.0  ┆ 2.6       │
└──────┴───────────┘
```

#### Scenario: Both bounds
- **WHEN** `clip(-1.0, 1.0)` runs on -2.1 and 2.6
- **THEN** the result is -1.0 and 1.0

### Requirement: Trigonometry
Expressions SHALL have `sin`, `cos`, `tan`, `cot`, `arcsin`, `arccos`, `arctan`, `sinh`,
`cosh`, `tanh`, `arcsinh`, `arccosh`, `arctanh`, `degrees` and `radians`, working in
radians, and `arctan2(y, x)` SHALL return the angle of the point (x, y).

```nim
let df = newDataFrame:
  deg: [0.0, 90.0, 180.0]
echo df.select(col.deg.radians.sin.round(3).alias("sin"),
               arctan2(lit(1.0), lit(1.0)).degrees.alias("atan2"))
```

```text
shape: (3, 2)
┌─────┬───────┐
│ sin ┆ atan2 │
│ --- ┆ ---   │
│ f64 ┆ f64   │
╞═════╪═══════╡
│ 0.0 ┆ 45.0  │
│ 1.0 ┆ 45.0  │
│ 0.0 ┆ 45.0  │
└─────┴───────┘
```

#### Scenario: Degrees round trip
- **WHEN** `radians` and then `degrees` run on 90.0
- **THEN** the result is 90.0

### Requirement: NaN and infinity
`isNan`, `isNotNan`, `isFinite` and `isInfinite` SHALL test float values (nulls give
null), `fillNan(value)` SHALL replace NaN with a literal or expression, `dropNans` SHALL
remove NaN values and `Expr.dropNulls` SHALL remove nulls. NaN SHALL stay distinct from
null, as in Polars.

```nim
import std/math
let df = newDataFrame:
  x: [1.0, NaN, Inf, nil]
echo df.select(col.x.isNan.alias("nan"), col.x.isFinite.alias("finite"),
               col.x.fillNan(0.0).alias("filled"))
echo df.select(col.x.dropNans.dropNulls)
```

```text
shape: (4, 3)
┌───────┬────────┬────────┐
│ nan   ┆ finite ┆ filled │
│ ---   ┆ ---    ┆ ---    │
│ bool  ┆ bool   ┆ f64    │
╞═══════╪════════╪════════╡
│ false ┆ true   ┆ 1.0    │
│ true  ┆ false  ┆ 0.0    │
│ false ┆ false  ┆ inf    │
│ null  ┆ null   ┆ null   │
└───────┴────────┴────────┘
shape: (2, 1)
┌─────┐
│ x   │
│ --- │
│ f64 │
╞═════╡
│ 1.0 │
│ inf │
└─────┘
```

#### Scenario: NaN is not null
- **WHEN** `isNull` runs on a column holding NaN
- **THEN** the result is false

#### Scenario: fillNan leaves nulls
- **WHEN** `fillNan(0.0)` runs on NaN and null
- **THEN** the result is 0.0 and null

### Requirement: Dot product
`a.dot(b)` SHALL return the sum of the elementwise products of two columns, as an
aggregation.

```nim
let df = newDataFrame:
  a: [1, 2, 3]
  b: [4, 5, 6]
echo df.select(col.a.dot(col.b))
```

```text
shape: (1, 1)
┌─────┐
│ a   │
│ --- │
│ i64 │
╞═════╡
│ 32  │
└─────┘
```

#### Scenario: Dot of two integer columns
- **WHEN** `col.a.dot(col.b)` runs on a = 1, 2, 3 and b = 4, 5, 6
- **THEN** the result is one row holding 32
