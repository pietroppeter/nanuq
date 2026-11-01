import std/[unittest, options, math]
import pkg/arraymancer
import nanuq, nanuq/arraymancer

suite "Arraymancer tensors":
  let df = newDataFrame(series("x", [1.0, 2.0, 3.0]), series("n", [4, 5, 6]))
  test "column and series to tensor":
    check df.toTensor("x", float) == [1.0, 2.0, 3.0].toTensor
    check df["n"].toTensor(int) == [4, 5, 6].toTensor
    check df["n"].toTensor(float) == [4.0, 5.0, 6.0].toTensor
  test "frame to 2-D tensor":
    let t = df.toTensor(float)
    check t.shape[0] == 3 and t.shape[1] == 2
    check t[1, 1] == 5.0
    check df.toTensor(int, ["n"]).shape[1] == 1
  test "nulls":
    let g = newDataFrame(series("a", [some(1.0), none(float)]), series("b", [some(1), none(int)]))
    check g.toTensor("a", float)[1].isNaN
    check g.toTensor("b", float)[1].isNaN
    expect InvalidOperationError: discard g.toTensor("b", int)
  test "tensor to series and frame":
    check [1.5, 2.5].toTensor.toSeries("v").toList(float) == @[1.5, 2.5]
    let back = df.toTensor(float).toDataFrame(["x", "n"])
    check back.columns == @["x", "n"]
    check back.toList("n", float) == @[4.0, 5.0, 6.0]
    check [[1, 2], [3, 4]].toTensor.toDataFrame.columns == @["column_0", "column_1"]
    expect ValueError: discard [[1, 2]].toTensor.toDataFrame(["one"])
