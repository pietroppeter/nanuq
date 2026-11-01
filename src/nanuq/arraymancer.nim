## Copying numeric columns between Nanuq and
## `Arraymancer <https://github.com/mratsim/Arraymancer>`_ tensors, like Python
## Polars' `to_numpy` / `from_numpy`. The data is copied. Arraymancer is an
## optional dependency: only this module needs it.
##
## .. code-block:: nim
##   import nanuq, nanuq/arraymancer
##
##   let df = newDataFrame(series("x", [1.0, 2.0]), series("y", [3.0, 4.0]))
##   let t = df.toTensor(float)          # 2 x 2, one row per row of df
##   echo t.toDataFrame(["x", "y"])
##
## Nulls become NaN in float tensors; integer and boolean columns with nulls
## raise `InvalidOperationError`.

import std/[options, math]
import pkg/arraymancer
import ../nanuq

type TensorValue = int | float | bool

proc values[T: TensorValue](df: nanuq.DataFrame, column: string, _: typedesc[T]): seq[T] =
  when T is float:
    if df.hasNulls(column):
      for v in df.cast({column: Float64}).toList(column, Option[float]):
        result.add v.get(NaN)
    else:
      result = df.cast({column: Float64}).toList(column, float)
  else:
    result = df.toList(column, T)

proc toTensor*[T: TensorValue](s: Series, _: typedesc[T]): Tensor[T] =
  ## The values of `s` as a 1-D tensor (integers become floats with `float`).
  values(s.toFrame, s.name, T).toTensor

proc toTensor*[T: TensorValue](df: nanuq.DataFrame, column: string, _: typedesc[T]): Tensor[T] =
  ## One column as a 1-D tensor.
  values(df, column, T).toTensor

proc toTensor*[T: TensorValue](df: nanuq.DataFrame, _: typedesc[T],
                               columns: openArray[string] = []): Tensor[T] =
  ## The `columns` (all by default) as a 2-D tensor with one row per row of `df`
  ## and one column per column, like Python's `DataFrame.to_numpy`.
  let names = if columns.len == 0: df.columns else: @columns
  result = newTensor[T](df.height, names.len)
  for j, name in names:
    let v = values(df, name, T)
    for i in 0 ..< v.len: result[i, j] = v[i]

proc toSeries*[T: TensorValue](t: Tensor[T], name: string): Series =
  ## A 1-D tensor as a Series.
  if t.rank != 1:
    raise newException(ValueError, "toSeries needs a 1-D tensor, not rank " & $t.rank)
  series(name, t.toSeq1D)

proc toDataFrame*[T: TensorValue](t: Tensor[T], columns: openArray[string] = []): nanuq.DataFrame =
  ## A 2-D tensor as a frame, one column per tensor column, named `columns` or
  ## column_0, column_1, ... (Python's `pl.from_numpy`).
  if t.rank != 2:
    raise newException(ValueError, "toDataFrame needs a 2-D tensor, not rank " & $t.rank)
  if columns.len > 0 and columns.len != t.shape[1]:
    raise newException(ValueError, "toDataFrame got " & $columns.len & " names for " &
                       $t.shape[1] & " columns")
  var cols: seq[Series]
  for j in 0 ..< t.shape[1]:
    let name = if columns.len > 0: columns[j] else: "column_" & $j
    cols.add series(name, t[_, j].squeeze(1).toSeq1D)
  newDataFrame(cols)
