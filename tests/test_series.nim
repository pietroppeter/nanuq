import std/[unittest, options, strutils, algorithm]
import nanuq

let df = newDataFrame(series("oni", [0.5, -1.0, 2.0, 1.2]), series("y", [1, 2, 3, 4]))

suite "series handles":
  test "from a frame":
    let s = df["oni"]
    check s.name == "oni"
    check s.len == 4
    check s.dtype == Float64
    check df.getColumn("y").toList(int) == @[1, 2, 3, 4]
    check df.toSeries(-1).name == "y"
    check s[2, float] == 2.0
    check s.nullCount == 0
  test "display":
    check ($df["y"]).startsWith("shape: (4,)\nSeries: 'y' [i64]")
  test "missing column":
    expect ColumnNotFoundError: discard df["nope"]
  test "rename, frame, cast":
    let s = df["y"].alias("year")
    check s.name == "year"
    check s.toFrame.columns == @["year"]
    check df["y"].cast(float).dtype == Float64
  test "nulls":
    let s = series("a", [some(1), none(int)])
    check s.toList(Option[int]) == @[some(1), none(int)]
    check s.nullCount == 1

suite "series operations":
  let s = df["oni"]
  test "aggregations give one value":
    check s.sum.item(float) == 2.7
    check s.max.item(float) == 2.0
    check s.argMax.item(int) == 2
    expect InvalidOperationError: discard s.item(float)
  test "arithmetic and comparisons":
    check (s * 2).toList(float) == @[1.0, -2.0, 4.0, 2.4]
    check (10 - df["y"]).toList(int) == @[9, 8, 7, 6]
    check (s > 0.6).toList(bool) == @[false, false, true, true]
    check (df["y"] + df["y"]).toList(int) == @[2, 4, 6, 8]
    check (df["y"] + df["y"]).name == "y"
  test "filter and methods with arguments":
    check s.filter(s > 0).toList(float) == @[0.5, 2.0, 1.2]
    check s.rollingMean(2).toList(Option[float]) == @[none(float), some(-0.25), some(0.5), some(1.6)]
    check s.shift(1, fillValue = 0.0).toList(float) == @[0.0, 0.5, -1.0, 2.0]
    check s.sort(descending = true).toList(float) == @[2.0, 1.2, 0.5, -1.0]
    check s.topK(2).toList(float).sorted == @[1.2, 2.0]
    check s.cut([0.0], labels = ["cold", "warm"]).toList(string) == @["warm", "cold", "warm", "warm"]
  test "value counts":
    let vc = series("p", ["a", "b", "a"]).valueCounts(sort = true)
    check vc.toList("count", int) == @[2, 1]
  test "back into a frame":
    check df.withColumns((s * 10).alias("big")).toList("big", float) == @[5.0, -10.0, 20.0, 12.0]
    check df.select(col.y + lit(df["y"])).toList("y", int) == @[2, 4, 6, 8]
