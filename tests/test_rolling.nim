import std/[unittest, options, math]
import nanuq

proc floats(xs: openArray[float]): DataFrame = newDataFrame(series("x", xs))
proc one(e: Expr, df: DataFrame): DataFrame = df.select(e.alias("r"))

suite "fixed windows":
  test "window not full yet":
    let df = newDataFrame(series("x", [1, 2, 3, 4]))
    check col("x").rollingSum(3).one(df).toList("r", Option[int]) ==
      @[none(int), none(int), some(6), some(9)]
  test "minSamples and center":
    let df = floats([1.0, 2.0, 3.0, 4.0])
    check col("x").rollingMean(2, minSamples = 1).one(df).toList("r", float) ==
      @[1.0, 1.5, 2.5, 3.5]
    check col("x").rollingMean(3, center = true).one(df).toList("r", Option[float]) ==
      @[none(float), some(2.0), some(3.0), none(float)]
  test "weights":
    let df = floats([2.0, 4.0])
    check col("x").rollingSum(2, weights = [0.5, 1.0]).one(df).toList("r", Option[float])[1] ==
      some(5.0)
  test "min, max, median, quantile, std, var":
    let df = floats([3.0, 1.0, 2.0])
    check col("x").rollingMin(3).one(df).toList("r", Option[float])[2] == some(1.0)
    check col("x").rollingMax(3).one(df).toList("r", Option[float])[2] == some(3.0)
    check col("x").rollingMedian(3).one(df).toList("r", Option[float])[2] == some(2.0)
    check col("x").rollingQuantile(1.0, 3).one(df).toList("r", Option[float])[2] == some(3.0)
    check col("x").rollingVar(3).one(df).toList("r", Option[float])[2] == some(1.0)
    check col("x").rollingStd(3).one(df).toList("r", Option[float])[2] == some(1.0)
    check col("x").rollingVar(3, ddof = 0).one(df).toList("r", Option[float])[2].get - 2.0/3.0 < 1e-12
  test "invalid window":
    expect ValueError: discard col("x").rollingMean(0)
    expect ValueError: discard col("x").rollingMean(2, weights = [1.0])

suite "time windows":
  test "gaps in the dates":
    let df = newDataFrame(series("day", [date(2026, 7, 1), date(2026, 7, 2), date(2026, 7, 5),
                                         date(2026, 7, 6)]), series("rain", [4, 0, 10, 2]))
    check col("rain").rollingSumBy("day", 3.days).one(df).toList("r", int) == @[4, 4, 10, 12]
    check col("rain").rollingMaxBy(col("day"), "3d").one(df).toList("r", int) == @[4, 4, 10, 10]
    check col("rain").rollingMeanBy("day", 2.days, closed = ClosedWindow.Both)
      .one(df).toList("r", float) == @[4.0, 2.0, 10.0, 6.0]

suite "ewm":
  let df = floats([14.0, 15.0, 13.0, 16.0])
  test "span and alpha agree":
    check col("x").ewmMean(span = 3).one(df).toList("r", float) ==
      col("x").ewmMean(alpha = 0.5).one(df).toList("r", float)
    check col("x").ewmMean(com = 1).one(df).toList("r", float) ==
      col("x").ewmMean(alpha = 0.5).one(df).toList("r", float)
  test "unadjusted recursion":
    let r = col("x").ewmMean(alpha = 0.5, adjust = false).one(df).toList("r", float)
    check r == @[14.0, 14.5, 13.75, 14.875]
  test "std and var":
    let v = col("x").ewmVar(alpha = 0.5).one(df).toList("r", Option[float])
    let s = col("x").ewmStd(alpha = 0.5).one(df).toList("r", Option[float])
    check abs(sqrt(v[3].get) - s[3].get) < 1e-12
  test "exactly one decay parameter":
    expect ValueError: discard col("x").ewmMean()
    expect ValueError: discard col("x").ewmMean(com = 1, alpha = 0.5)
    expect ValueError: discard col("x").ewmMean(alpha = 1.5)

suite "interpolate":
  test "linear and nearest":
    let df = newDataFrame(series("x", [some(1), none(int), some(3), none(int)]))
    check col("x").interpolate.one(df).toList("r", Option[float]) ==
      @[some(1.0), some(2.0), some(3.0), none(float)]
    let n = newDataFrame(series("x", [some(1.0), none(float), none(float), some(4.0)]))
    check col("x").interpolate(InterpolationMethod.Nearest).one(n).toList("r", float) ==
      @[1.0, 1.0, 4.0, 4.0]
  test "by distances":
    let df = newDataFrame(series("day", [1, 2, 4]), series("t", [some(10.0), none(float), some(16.0)]))
    check col("t").interpolateBy("day").one(df).toList("r", float) == @[10.0, 12.0, 16.0]
