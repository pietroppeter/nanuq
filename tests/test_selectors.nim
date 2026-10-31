import std/unittest
import nanuq

proc log(): DataFrame =
  newDataFrame(series("station", ["a", "a", "b"]), series("bears", [1, 2, 3]),
               series("cubs", [0, 1, 1]), series("weight", [100.0, 200.0, 300.0]),
               series("collared", [true, false, true]))

suite "by type":
  test "typeclasses":
    check log().select(col(SomeNumber)).columns == @["bears", "cubs", "weight"]
    check log().select(col(SomeInteger)).columns == @["bears", "cubs"]
    check log().select(col(SomeSignedInt)).columns == @["bears", "cubs"]
    check log().select(col(SomeUnsignedInt)).columns.len == 0
    check log().select(col(SomeFloat)).columns == @["weight"]

  test "concrete types and unions":
    check log().select(col(int)).columns == @["bears", "cubs"]
    check log().select(col(string)).columns == @["station"]
    check log().select(col(bool)).columns == @["collared"]
    check log().select(col(float, string)).columns == @["station", "weight"]
    check log().select(col(SomeFloat, bool)).columns == @["weight", "collared"]

  test "not a column type":
    check not compiles(col(seq[int]))

suite "by name":
  test "several names, all, regex":
    check log().select(col("weight", "station")).columns == @["weight", "station"]
    check log().select(all()).columns == log().columns
    let w = newDataFrame(series("weight_kg", [1.0]), series("weight_lb", [2.2]), series("name", ["x"]))
    check w.select(col("^weight_.*$")).columns == @["weight_kg", "weight_lb"]
    check col("a") is Expr
    check col("a", "b") is Selector

  test "missing name raises":
    expect NanuqError: discard log().select(col("bears", "nope"))

suite "exclude":
  test "all but some":
    check log().select(all().exclude("station")).columns == @["bears", "cubs", "weight", "collared"]
    check log().select(col(SomeNumber).exclude("cubs", "bears")).columns == @["weight"]

suite "selectors as expressions":
  test "mean per group of every numeric column but one":
    let r = log().groupBy(col("station")).agg(col(SomeNumber).exclude("cubs").mean).sort("station").collect
    check r.columns == @["station", "bears", "weight"]
    check r.toSeq("bears", float) == @[1.5, 3.0]
    check r.toSeq("weight", float) == @[150.0, 300.0]

  test "withColumns over many columns":
    let r = log().withColumns(col(SomeInteger) * 10)
    check r.toSeq("bears", int) == @[10, 20, 30]
    check r.toSeq("cubs", int) == @[0, 10, 10]

  test "two aggregations with suffixes":
    let df = newDataFrame(series("a", [1.0, 3.0]), series("b", [2.0, 6.0]))
    let r = df.select(col(SomeFloat).mean.name.suffix("_mean"), col(SomeFloat).max.name.suffix("_max"))
    check r.columns == @["a_mean", "b_mean", "a_max", "b_max"]
    check r.toSeq("b_max", float) == @[6.0]
    check df.select(col("a").name.prefix("avg_")).columns == @["avg_a"]

  test "duplicate names without a suffix raise":
    let df = newDataFrame(series("a", [1.0]))
    expect NanuqError: discard df.select(col(SomeFloat).mean, col(SomeFloat).max)

  test "$ shows the selector":
    check ($col(SomeNumber)).len > 0
