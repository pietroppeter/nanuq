import std/[unittest, options, math]
import nanuq

proc ints(xs: openArray[int]): DataFrame = newDataFrame(series("x", xs))
proc one(e: Expr, df: DataFrame): DataFrame = df.select(e.alias("r"))

suite "shift and differences":
  test "shift down, up, with fill":
    let df = ints([1, 2, 3])
    check col("x").shift.one(df).toList("r", Option[int]) == @[none(int), some(1), some(2)]
    check col("x").shift(-1, fillValue = 0).one(df).toList("r", int) == @[2, 3, 0]
  test "shift within groups":
    let df = newDataFrame(series("g", ["a", "a", "b", "b"]), series("x", [1, 2, 3, 4]))
    check col("x").shift.over(col("g")).one(df).toList("r", Option[int]) ==
      @[none(int), some(1), none(int), some(3)]
  test "diff":
    let df = ints([1, 4, 9])
    check col("x").diff.one(df).toList("r", Option[int]) == @[none(int), some(3), some(5)]
    check col("x").diff(nullBehavior = NullBehavior.Drop).one(df).toList("r", int) == @[3, 5]
    check col("x").diff(2).one(df).toList("r", Option[int]) == @[none(int), none(int), some(8)]
  test "pctChange":
    let r = col("x").pctChange.one(ints([10, 11, 22])).toList("r", Option[float])
    check r[0].isNone
    check abs(r[1].get - 0.1) < 1e-12
    check r[2].get == 1.0

suite "cumulative":
  test "sum, prod, min, max":
    let df = ints([3, 1, 5, 2])
    check col("x").cumSum.one(df).toList("r", int) == @[3, 4, 9, 11]
    check col("x").cumSum(reverse = true).one(df).toList("r", int) == @[11, 8, 7, 2]
    check col("x").cumProd.one(df).toList("r", int) == @[3, 3, 15, 30]
    check col("x").cumMin.one(df).toList("r", int) == @[3, 1, 1, 1]
    check col("x").cumMax.one(df).toList("r", int) == @[3, 3, 5, 5]
  test "count skips nulls":
    let df = newDataFrame(series("x", [some(1), none(int), some(3)]))
    check col("x").cumCount.one(df).toList("r", int) == @[1, 1, 2]

suite "runs and peaks":
  test "rleId":
    let df = newDataFrame(series("x", [true, true, false, true]))
    check col("x").rleId.one(df).toList("r", int) == @[0, 0, 1, 2]
    let lens = df.withColumns(col("x").rleId.alias("run")).groupBy(col("run"))
      .agg(col("x").len.alias("n")).sort("run").collect
    check lens.toList("n", int) == @[2, 1, 1]
  test "peaks":
    let df = ints([1, 3, 2, 0, 4, 1])
    check col("x").peakMax.one(df).toList("r", bool) == @[false, true, false, false, true, false]
    check col("x").peakMin.one(df).toList("r", bool) == @[false, false, false, true, false, false]

suite "aggregations":
  test "product, argMin, argMax":
    check col("x").product.one(ints([2, 3, 4])).toList("r", int) == @[24]
    check col("x").argMin.one(ints([5, 1, 1, 9])).toList("r", int) == @[1]
    check col("x").argMax.one(ints([5, 1, 1, 9])).toList("r", int) == @[3]
  test "mode":
    check col("x").mode.one(ints([1, 2, 2, 3, 3])).sort("r").toList("r", int) == @[2, 3]
  test "skew and kurtosis":
    let df = newDataFrame(series("x", [1.0, 2.0, 3.0]))
    check col("x").skew.one(df).toList("r", float) == @[0.0]
    check abs(col("x").kurtosis.one(df).toList("r", float)[0] - (-1.5)) < 1e-12
    check abs(col("x").kurtosis(fisher = false).one(df).toList("r", float)[0] - 1.5) < 1e-12
