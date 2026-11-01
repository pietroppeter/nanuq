# Spec Delta

## ADDED Requirements

### Requirement: Columns to tensors
The optional module `nanuq/arraymancer` SHALL provide `toTensor(series, T)`,
`toTensor(df, column, T)` and `toTensor(df, T, columns)`, copying values into an
Arraymancer `Tensor[T]` for T in int, float and bool; the frame version SHALL give a 2-D
tensor with one row per row of the frame. Nulls SHALL become NaN in float tensors and
SHALL raise `InvalidOperationError` for int and bool.

```nim
import pkg/arraymancer, nanuq/arraymancer
let df = newDataFrame:
  oni: [2.4, 2.6, 2.0]
  temp: [14.7, 15.0, 15.2]
let t = df.toTensor(float)
echo t.shape[0], "x", t.shape[1], " ", t[1, 0]
```

```text
TBD
```

#### Scenario: Nulls in a float tensor
- **WHEN** a float column with a null is copied with `toTensor("a", float)`
- **THEN** the tensor holds NaN at that position

### Requirement: Tensors to columns
`toSeries(tensor, name)` SHALL copy a 1-D tensor into a Series, and
`toDataFrame(tensor, columns)` SHALL copy a 2-D tensor into a frame with one column per
tensor column, named `columns` or column_0, column_1, ...

```nim
import pkg/arraymancer, nanuq/arraymancer
echo [[1.0, 2.0], [3.0, 4.0]].toTensor.toDataFrame(["a", "b"])
```

```text
TBD
```

#### Scenario: Wrong rank
- **WHEN** `toSeries` is called on a 2-D tensor
- **THEN** `ValueError` is raised
