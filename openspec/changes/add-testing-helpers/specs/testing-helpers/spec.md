# Spec Delta

## ADDED Requirements

### Requirement: Comparing frames in tests
`assertFrameEqual(left, right, checkRowOrder = true, checkColumnOrder = true,
checkDtypes = true, checkExact = false, rtol = 1e-5, atol = 1e-8)` in `nanuq/testing`
SHALL return when the frames (or collected LazyFrames) have the same columns, types and
rows, with nulls equal to nulls and floats equal within `atol + rtol * abs(right)` unless
`checkExact`, and raise `AssertionDefect` naming the first difference otherwise.
`assertFrameNotEqual` SHALL do the opposite.

```nim
import nanuq/testing
let df = newDataFrame(series("bear", @["Ada", "Bo"]), series("kg", @[410.0, 380.5]))
assertFrameEqual(df, newDataFrame(series("bear", @["Ada", "Bo"]), series("kg", @[410.0, 380.5000001])))
try:
  assertFrameEqual(df, newDataFrame(series("bear", @["Ada", "Cy"]), series("kg", @[410.0, 380.5])))
except AssertionDefect as e:
  echo e.msg
```

```text
TBD
```

#### Scenario: Ignoring order
- **WHEN** two frames hold the same rows and columns in another order and both order checks are off
- **THEN** `assertFrameEqual` returns

### Requirement: Comparing Series in tests
`assertSeriesEqual(left, right, checkDtypes = true, checkNames = true, checkOrder = true,
checkExact = false, rtol = 1e-5, atol = 1e-8)` SHALL compare two Series the same way,
also checking their names unless `checkNames = false`; `assertSeriesNotEqual` SHALL do
the opposite.

```nim
import nanuq/testing
let a = series("kg", @[410, 380])
assertSeriesEqual(a, series("mass", @[410, 380]), checkNames = false)
assertSeriesNotEqual(a, series("kg", @[410, 381]))
echo "ok"
```

```text
TBD
```

#### Scenario: NaN
- **WHEN** both Series hold NaN at the same row
- **THEN** `assertSeriesEqual` returns
