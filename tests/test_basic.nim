import std/[os, unittest, strutils, math]
import nanuq

const dataDir = currentSourcePath.parentDir.parentDir / "src" / "nanuq" / "data"

suite "dataframe construction":
  test "from series":
    let df = newDataFrame(series("a", [1, 2, 3]), series("b", ["x", "y", "z"]),
                          series("c", [1.5, 2.5, 3.5]), series("d", [true, false, true]))
    check df.shape == (3, 4)
    check df.columns == @["a", "b", "c", "d"]
    check df.dtype("a") == "i64"
    check df.dtype("b") == "str"
    check df.dtype("c") == "f64"
    check df.dtype("d") == "bool"
    check df["b", 1, string] == "y"
    check df.toSeq("a", int) == @[1, 2, 3]
    check "shape: (3, 4)" in $df

  test "length mismatch raises":
    expect NanuqError:
      discard newDataFrame(series("a", [1, 2, 3]), series("b", [1, 2]))

  test "empty series":
    let df = newDataFrame(series("a", newSeq[int]()))
    check df.shape == (0, 1)

suite "csv":
  test "read":
    let df = readCsv(dataDir / "penguins.csv", nullValues = ["NA"])
    check df.shape == (344, 8)
    check df.dtype("bill_length_mm") == "f64"
    check df.getFloat("bill_length_mm", 0) == 39.1

  test "missing file raises":
    expect NanuqError:
      discard readCsv("does/not/exist.csv")

  test "roundtrip":
    let df = newDataFrame(series("a", [1, 2]), series("b", ["p", "q"]))
    let path = getTempDir() / "nanuq_roundtrip.csv"
    df.writeCsv(path)
    let back = readCsv(path)
    check back.shape == (2, 2)
    check back["a", 1, int] == 2
    check back["b", 0, string] == "p"
    removeFile(path)

suite "expressions and queries":
  let df = newDataFrame(series("g", ["a", "b", "a", "b", "a"]),
                        series("x", [1, 2, 3, 4, 5]),
                        series("y", [10.0, 20.0, 30.0, 40.0, 50.0]))

  test "filter":
    let r = df.filter(col("x") >= 3 and col("g") == "a")
    check r.toSeq("x", int) == @[3, 5]

  test "with columns arithmetic":
    let r = df.withColumns((col("x") * 2 + col("y")).alias("z"))
    check r.toSeq("z", float) == @[12.0, 24.0, 36.0, 48.0, 60.0]

  test "select aggregations":
    let r = df.select(col("x").sum.alias("s"), col("y").mean.alias("m"),
                      col("x").max.alias("mx"), col("g").nUnique.alias("u"))
    check r.shape == (1, 4)
    check r["s", 0, int] == 15
    check r["m", 0, float] == 30.0
    check r["mx", 0, int] == 5
    check r["u", 0, int] == 2

  test "group by":
    let r = df.lazy.groupBy(col("g"))
              .agg(col("x").sum.alias("sx"), col("y").std.alias("sd"))
              .sort("g").collect
    check r.toSeq("g", string) == @["a", "b"]
    check r.toSeq("sx", int) == @[9, 6]
    check almostEqual(r["sd", 0, float], 20.0)

  test "sort and limit":
    let r = df.lazy.sort("x", descending = true).limit(2).collect
    check r.toSeq("x", int) == @[5, 4]

  test "expression display":
    check "col(\"x\")" in $(col("x") + 1)

  test "explain":
    let plan = df.lazy.filter(col("x") > 1).select(col("y")).explain
    check "FILTER" in plan.toUpperAscii or "SELECTION" in plan.toUpperAscii

  test "bad column raises":
    expect NanuqError:
      discard df.select(col("nope"))
    expect NanuqError:
      discard df.getInt("nope", 0)
