# Spec Delta

## ADDED Requirements

### Requirement: Null-aware comparisons and closeness
`eqMissing(other)` and `neMissing(other)` SHALL compare as `==` and `!=` with null equal
to null, never giving null. `isClose(other, absTol = 0.0, relTol = 1e-9, nansEqual =
false)` SHALL be true where `abs(a - b) <= max(relTol * max(abs(a), abs(b)), absTol)`.

```nim
let df = newDataFrame(series("a", [some(1.0), none(float)]), series("b", [some(1.05), none(float)]))
echo df.select(col("a").eqMissing(col("b")).alias("eq"),
               col("a").isClose(col("b"), absTol = 0.1).alias("close"))
```

```text
TBD
```

#### Scenario: Nulls
- **WHEN** `eqMissing` compares null with null
- **THEN** the result is true

### Requirement: More expression functions
`nth(indices)` SHALL select columns by position (negative from the end).
`cumulativeEval(expr, minSamples = 1)` SHALL run `expr` on the growing window up to each
row, `roundSigFigs(digits)` SHALL round to significant figures, `reinterpret(signed)`
SHALL read 64-bit integer bits as Int64 or UInt64, and `concatArr(exprs)` SHALL build
fixed-size arrays per row.

```nim
let df = newDataFrame(series("x", @[1.0, 22.0, 333.0]), series("y", @[4.0, 5.0, 6.0]))
echo df.select(nth(-1), col("x").cumulativeEval(element().sum).alias("cum"),
               col("x").roundSigFigs(1).alias("sig"), concatArr(col("x"), col("y")).alias("xy"))
```

```text
TBD
```

#### Scenario: Cumulative sum
- **WHEN** `cumulativeEval(element().sum)` runs on 1, 2, 3
- **THEN** the result is 1, 3, 6
