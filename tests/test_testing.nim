import std/[unittest, options, strutils]
import nanuq, nanuq/testing

suite "testing helpers":
  let df = newDataFrame(series("bear", @["Ada", "Bo"]), series("kg", @[410.0, 380.5]))

  test "equal frames":
    assertFrameEqual(df, df)
    assertFrameEqual(df.lazy, df.lazy)
    let close = newDataFrame(series("bear", @["Ada", "Bo"]), series("kg", @[410.000001, 380.5]))
    assertFrameEqual(df, close)
    let reordered = newDataFrame(series("kg", @[380.5, 410.0]), series("bear", @["Bo", "Ada"]))
    assertFrameEqual(df, reordered, checkRowOrder = false, checkColumnOrder = false)

  test "differences":
    let other = newDataFrame(series("bear", @["Ada", "Cy"]), series("kg", @[410.0, 380.5]))
    try:
      assertFrameEqual(df, other)
      check false
    except AssertionDefect as e:
      check "column \"bear\"" in e.msg
      check "row 1" in e.msg
      check "Bo != Cy" in e.msg
    let close = newDataFrame(series("bear", @["Ada", "Bo"]), series("kg", @[410.000001, 380.5]))
    expect AssertionDefect:
      assertFrameEqual(df, close, checkExact = true)
    expect AssertionDefect:
      assertFrameEqual(df, df.select("kg", "bear"))
    expect AssertionDefect:
      assertFrameEqual(df, df.slice(0, 1))
    let ints = df.withColumns(col("kg").cast(Int64))
    expect AssertionDefect:
      assertFrameEqual(df.select("bear"), df.select(col("bear").cast(Categorical)))
    assertFrameEqual(df.select("bear"), df.select(col("bear").cast(Categorical)), checkDtypes = false)
    assertFrameNotEqual(df, ints)

  test "series":
    let a = series("x", [some(1), none(int), some(3)])
    assertSeriesEqual(a, series("x", [some(1), none(int), some(3)]))
    expect AssertionDefect:
      assertSeriesEqual(a, series("y", [some(1), none(int), some(3)]))
    assertSeriesEqual(a, series("y", [some(1), none(int), some(3)]), checkNames = false)
    expect AssertionDefect:
      assertSeriesEqual(a, series("x", [some(1), some(2), some(3)]))
    assertSeriesNotEqual(a, series("x", [some(1), some(2), some(3)]))
    assertSeriesEqual(series("f", @[NaN, 1.0]), series("f", @[NaN, 1.0]))
    assertSeriesEqual(series("x", @[3, 1, 2]), series("x", @[1, 2, 3]), checkOrder = false)
