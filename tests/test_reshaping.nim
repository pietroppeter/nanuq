import std/[unittest, options, math]
import nanuq

proc long(): DataFrame =
  newDataFrame(series("year", [2023, 2023, 2024, 2024]),
               series("season", ["DJF", "JJA", "DJF", "JJA"]),
               series("oni", [-0.7, 1.1, 1.8, 0.0]))

suite "pivot":
  test "basic":
    let w = long().pivot("season", index = "year", values = "oni")
    check w.columns == @["year", "DJF", "JJA"]
    check w.toList("DJF", float) == @[-0.7, 1.8]
    check w.toList("JJA", float) == @[1.1, 0.0]
  test "values default to the rest, sorted columns":
    let w = long().pivot(["season"], index = ["year"], sortColumns = true)
    check w.columns == @["year", "DJF", "JJA"]
  test "aggregation":
    let df = newDataFrame(series("k", ["a", "a", "b"]), series("c", ["x", "x", "y"]),
                          series("v", [1, 2, 3]))
    let s = df.pivot("c", index = "k", values = "v", aggregateFunction = PivotAgg.Sum)
    check s.toList("x", int) == @[3, 0]  # as Python: an empty sum is 0
    let m = df.pivot("c", index = "k", values = "v", aggregateFunction = element().max)
    check m.toList("x", Option[int]) == @[some(2), none(int)]
    expect PolarsError:
      discard df.pivot("c", index = "k", values = "v")
  test "lazy with onColumns":
    let onCols = newDataFrame(series("season", ["JJA"]))
    let w = long().lazy.pivot("season", onCols, index = "year", values = "oni").collect
    check w.columns == @["year", "JJA"]
  test "needs index or values":
    expect InvalidOperationError:
      discard long().pivot("season")

suite "unpivot":
  test "index and names":
    let w = long().pivot("season", index = "year", values = "oni")
    let l = w.unpivot(index = "year", variableName = "season", valueName = "oni")
    check l.columns == @["year", "season", "oni"]
    check l.height == 4
    check l.sort(["year", "season"]).toList("oni", float) == @[-0.7, 1.1, 1.8, 0.0]
  test "explicit on, lazy":
    let w = newDataFrame(series("id", [1]), series("a", [10]), series("b", [20]))
    let l = w.lazy.unpivot(on = ["a"], index = "id").collect
    check l.toList("variable", string) == @["a"]
    check l.toList("value", int) == @[10]

suite "transpose":
  test "header and names":
    let df = newDataFrame(series("lima", [22.1, 24.3]), series("quito", [14.0, 14.2]))
    let t = df.transpose(includeHeader = true, headerName = "station", columnNames = ["jan", "feb"])
    check t.columns == @["station", "jan", "feb"]
    check t.toList("station", string) == @["lima", "quito"]
    check t.toList("feb", float) == @[24.3, 14.2]
  test "default names":
    check newDataFrame(series("a", [1, 2])).transpose.columns == @["column_0", "column_1"]

suite "partitionBy":
  test "order and key":
    let df = newDataFrame(series("p", ["w", "c", "w"]), series("y", [2015, 2020, 2023]))
    let parts = df.partitionBy("p", includeKey = false)
    check parts.len == 2
    check parts[0].columns == @["y"]
    check parts[0].toList("y", int) == @[2015, 2023]
    check parts[1].toList("y", int) == @[2020]
  test "several keys":
    let df = newDataFrame(series("a", [1, 1, 2]), series("b", ["x", "y", "x"]))
    check df.partitionBy(["a", "b"]).len == 3

suite "toDummies":
  test "all and dropFirst":
    let df = newDataFrame(series("p", ["warm", "cold", "warm"]))
    let d = df.toDummies()
    check d.columns.len == 2
    check "p_warm" in d.columns
    check d.toList("p_warm", int) == @[1, 0, 1]
    check df.toDummies(dropFirst = true).columns.len == 1
