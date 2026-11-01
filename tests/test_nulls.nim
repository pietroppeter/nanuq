import std/[os, unittest, strutils]
import nanuq

const dataDir = currentSourcePath.parentDir / "data"

proc gaps(): DataFrame =
  newDataFrame(series("a", [some(1), none(int), some(3)]),
               series("b", [some(1.5), some(2.5), none(float)]),
               series("c", [some(true), none(bool), some(false)]),
               series("d", [some("x"), none(string), some("z")]))

suite "bulk column reads":
  test "plain types":
    let df = newDataFrame(series("a", [1, 2]), series("b", [0.5, 1.5]),
                          series("c", [true, false]), series("d", ["p", "q"]))
    check df.toList("a", int) == @[1, 2]
    check df.toList("b", float) == @[0.5, 1.5]
    check df.toList("c", bool) == @[true, false]
    check df.toList("d", string) == @["p", "q"]

  test "dtype rules":
    let df = newDataFrame(series("i", [1, 2]), series("f", [1.5, 2.5]), series("s", ["a", "b"]))
    check df.toList("i", float) == @[1.0, 2.0]     # integers read as floats
    check df.toList("i", string) == @["1", "2"]     # anything reads as string
    check df.toList("f", string) == @["1.5", "2.5"]
    expect PolarsError: discard df.toList("f", int)  # no silent truncation
    expect PolarsError: discard df.toList("s", float)
    expect PolarsError: discard df.toList("i", bool)

  test "empty and unicode strings":
    let df = newDataFrame(series("s", ["", "ünïcödé", "🐻‍❄️"]))
    check df.toList("s", string) == @["", "ünïcödé", "🐻‍❄️"]
    let empty = newDataFrame(series("s", newSeq[string]()))
    check empty.toList("s", string).len == 0

  test "large column":
    var xs = newSeq[float](200_000)
    for i in 0 ..< xs.len: xs[i] = i.float
    let df = newDataFrame(series("x", xs))
    check df.toList("x", float) == xs

  test "missing column raises":
    expect PolarsError: discard gaps().toList("nope", int)

suite "nulls":
  test "read as Option":
    let df = gaps()
    check df.toList("a", Option[int]) == @[some(1), none(int), some(3)]
    check df.toList("b", Option[float]) == @[some(1.5), some(2.5), none(float)]
    check df.toList("c", Option[bool]) == @[some(true), none(bool), some(false)]
    check df.toList("d", Option[string]) == @[some("x"), none(string), some("z")]

  test "plain reads refuse nulls":
    let df = gaps()
    for col in ["a", "b", "c", "d"]:
      try:
        case col
        of "a": discard df.toList(col, int)
        of "b": discard df.toList(col, float)
        of "c": discard df.toList(col, bool)
        else: discard df.toList(col, string)
        check false
      except PolarsError as e:
        check ("'" & col & "'") in e.msg
    expect PolarsError: discard df["a", 1, int]
    expect PolarsError: discard df["d", 1, string]

  test "cells":
    let df = gaps()
    check df["a", 1, Option[int]] == none(int)
    check df["a", 2, Option[int]] == some(3)
    check df["c", 0, Option[bool]] == some(true)
    check df["d", 1, Option[string]] == none(string)
    check df["c", 2, bool] == false

  test "counting":
    let df = gaps()
    check df.nullCount("a") == 1
    check df.hasNulls("a")
    let full = newDataFrame(series("a", [1, 2]))
    check full.nullCount("a") == 0
    check not full.hasNulls("a")

  test "round trip keeps dtype":
    let df = gaps()
    check df.dtype("a") == Int64
    check df.dtype("b") == Float64
    check df.dtype("c") == Boolean
    check df.dtype("d") == String

  test "isNull and isNotNull":
    let df = gaps()
    check df.filter(col("a").isNotNull).toList("a", int) == @[1, 3]
    check df.filter(col("a").isNull).height == 1
    check "is_null" in $col("a").isNull

  test "fillNull":
    let df = gaps()
    check df.withColumns(col("a").fillNull(0)).toList("a", int) == @[1, 0, 3]
    check df.withColumns(col("d").fillNull("?")).toList("d", string) == @["x", "?", "z"]
    check df.withColumns(col("b").fillNull(col("b").mean)).toList("b", float) == @[1.5, 2.5, 2.0]

  test "dropNulls":
    let df = gaps()
    check df.dropNulls().toList("a", int) == @[1]   # only row 0 has no nulls
    check df.dropNulls("a").toList("a", int) == @[1, 3]
    check df.dropNulls(["a", "b"]).toList("a", int) == @[1]
    check df.lazy.dropNulls("d").collect.height == 2

suite "csv nulls":
  test "nullValues":
    let df = readCsv(dataDir / "with_na.csv", nullValues = ["NA"])
    check df.dtype("mass") == Int64
    check df.toList("mass", Option[int]) == @[some(3750), none(int), some(4250)]
    check df.toList("species", Option[string]) == @[some("Adelie"), some("Adelie"), none(string)]
    check df.dtype("flag") == Boolean
    check df.nullCount("flag") == 1

  test "without nullValues NA is a string":
    let df = readCsv(dataDir / "with_na.csv")
    check df.dtype("mass") == String
    check df.toList("mass", string)[1] == "NA"

suite "null literal":
  test "lit(nil) and fillNan(nil)":
    let df = newDataFrame(series("x", [1.0, NaN, 3.0]))
    check df.select(col.x.fillNan(nil)).toList("x", Option[float]) == @[some(1.0), none(float), some(3.0)]
    check df.select(col.x, lit(nil).alias("n")).nullCount("n") == 3
