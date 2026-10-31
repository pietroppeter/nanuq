import std/[os, unittest, strutils, math, sequtils]
import nanuq
from nanuq/ffi import lacksModernCpu

const dataDir = currentSourcePath.parentDir.parentDir / "src" / "nanuq" / "data"

suite "dataframe construction":
  test "from series":
    let df = newDataFrame(series("a", [1, 2, 3]), series("b", ["x", "y", "z"]),
                          series("c", [1.5, 2.5, 3.5]), series("d", [true, false, true]))
    check df.shape == (3, 4)
    check df.columns == @["a", "b", "c", "d"]
    check df.dtype("a") == Int64
    check df.dtype("b") == String
    check df.dtype("c") == Float64
    check df.dtype("d") == Boolean
    check df["b", 1, string] == "y"
    check df.toList("a", int) == @[1, 2, 3]
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
    check df.dtype("bill_length_mm") == Float64
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
    check r.toList("x", int) == @[3, 5]

  test "with columns arithmetic":
    let r = df.withColumns((col("x") * 2 + col("y")).alias("z"))
    check r.toList("z", float) == @[12.0, 24.0, 36.0, 48.0, 60.0]

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
    check r.toList("g", string) == @["a", "b"]
    check r.toList("sx", int) == @[9, 6]
    check almostEqual(r["sd", 0, float], 20.0)

  test "sort and limit":
    let r = df.lazy.sort("x", descending = true).limit(2).collect
    check r.toList("x", int) == @[5, 4]

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

suite "library":
  test "linked library matches the crate version":
    check polarsWrapperVersion() == nanuqLibVersion
    check nanuqLibVersion.len > 0
  test "CPU detection picks the legacy build without AVX2":
    check not lacksModernCpu("flags\t\t: fpu sse2 avx avx2 bmi1 bmi2 fma f16c movbe\n")
    check lacksModernCpu("flags\t\t: fpu sse2 avx\n")

suite "0.3 conveniences":
  test "toSeq from sequtils still works":
    let files = toSeq(walkFiles(dataDir / "*.csv"))
    check files.len >= 1

  test "block syntax":
    let a = newDataFrame:
      rider: ["Pogačar", "Seixas"]
      wins: [22, nil]
      "win %": [0.31, 0.12]
      ok: [true, false]
    check a.columns == @["rider", "wins", "win %", "ok"]
    check a.dtype("wins") == Int64
    check a.toList("wins", Option[int]) == @[some(22), none(int)]
    let b = newDataFrame(series("rider", ["Pogačar", "Seixas"]),
                         series("wins", [some(22), none(int)]),
                         series("win %", [0.31, 0.12]), series("ok", [true, false]))
    check $a == $b
    check newDataFrame().shape == (0, 0)
    let cols = @[series("x", [1])]
    check newDataFrame(cols).shape == (1, 1)
    template onlyNil(): untyped =
      newDataFrame:
        wins: [nil, nil]
    check not compiles(onlyNil())
    let strs = newDataFrame:
      s: ["a", nil]
    check strs.toList("s", Option[string]) == @[some("a"), none(string)]

  test "col shorthand":
    check $col.race == $col("race")
    check $col.len == $col("len")
    check $col.min == $col("min")
    check $col.end == $col("end")
    let df = newDataFrame:
      a: [1, 2]
      b: [1.5, 2.5]
    check df.select(col("a", "b")).width == 2
    check df.select(col(SomeFloat)).columns == @["b"]
    check df.select(col(float, int)).width == 2
