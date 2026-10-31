import std/[unittest, options]
import nanuq

proc weights(): DataFrame = newDataFrame(series("w", [100, 300, 900]))
proc one(e: Expr, df: DataFrame): DataFrame = df.select(e.alias("r"))

suite "conditionals":
  test "three-way chain":
    let size = `when`(col("w") < 150).then("cub").when(col("w") < 500).then("adult").otherwise("chonk")
    check size.one(weights()).toSeq("r", string) == @["cub", "adult", "chonk"]

  test "no otherwise gives null":
    let r = weights().select(`when`(col("w") < 150).then(1).alias("r"))
    check r.toSeq("r", Option[int]) == @[some(1), none(int), none(int)]

  test "expression values and string literals":
    let r = `when`(col("w") > 200).then(col("w") * 2).otherwise(0).one(weights())
    check r.toSeq("r", int) == @[0, 600, 1800]
    # a string is a value, not a column name
    let s = `when`(col("w") > 200).then("w").otherwise("light").one(weights())
    check s.toSeq("r", string) == @["light", "w", "w"]

  test "choose builds the same plan":
    let chain = `when`(col("w") < 150).then("cub").when(col("w") < 500).then("adult").otherwise("chonk")
    let macroed = choose:
      if col("w") < 150: "cub"
      elif col("w") < 500: "adult"
      else: "chonk"
    check $macroed == $chain
    check macroed.one(weights()).toSeq("r", string) == @["cub", "adult", "chonk"]

  test "choose on one line and without else":
    let df = newDataFrame(series("collared", [true, false]))
    let r = df.select(choose(if col("collared"): "tracked" else: "free").alias("status"))
    check r.toSeq("status", string) == @["tracked", "free"]
    let noElse = choose:
      if col("w") < 150: "cub"
    check noElse.one(weights()).toSeq("r", Option[string]) == @[some("cub"), none(string), none(string)]

  test "choose rejects other bodies":
    check not compiles(choose(col("w") + 1))

suite "membership and ranges":
  proc abc(): DataFrame = newDataFrame(series("a", [1, 2, 3]))

  test "isIn":
    check col("a").isIn([1, 3]).one(abc()).toSeq("r", bool) == @[true, false, true]
    let s = newDataFrame(series("s", ["x", "y"]))
    check s.select(col("s").isIn(["y"]).alias("r")).toSeq("r", bool) == @[false, true]

  test "isIn with nulls":
    let df = newDataFrame(series("a", [some(1), none(int)]), series("b", [some(1), none(int)]))
    check df.select(col("a").isIn([1]).alias("r")).toSeq("r", Option[bool])[0] == some(true)

  test "isBetween":
    check col("a").isBetween(1, 3).one(abc()).toSeq("r", bool) == @[true, true, true]
    check col("a").isBetween(1, 3, closed = Left).one(abc()).toSeq("r", bool) == @[true, true, false]
    check col("a").isBetween(1, 3, closed = None).one(abc()).toSeq("r", bool) == @[false, true, false]

suite "arithmetic":
  test "floor semantics of mod and div":
    let df = newDataFrame(series("a", [-7, 7]))
    check (col("a") mod 3).one(df).toSeq("r", int) == @[2, 1]
    check (col("a") div 3).one(df).toSeq("r", int) == @[-3, 2]

  test "power, abs, negation":
    let df = newDataFrame(series("a", [-3, 2]))
    check (col("a") ^ 2).one(df).toSeq("r", float) == @[9.0, 4.0]
    check col("a").pow(3).one(df).toSeq("r", float) == @[-27.0, 8.0]
    check (2 ^ col("a")).one(newDataFrame(series("a", [3]))).toSeq("r", float) == @[8.0]
    check col("a").abs.one(df).toSeq("r", int) == @[3, 2]
    check (-col("a")).one(df).toSeq("r", int) == @[3, -2]

  test "round":
    let df = newDataFrame(series("w", [1.23456, 2.5]))
    check col("w").round(2).one(df).toSeq("r", float) == @[1.23, 2.5]
    check col("w").round.one(df).toSeq("r", float) == @[1.0, 2.0]
    check col("w").round(mode = HalfAwayFromZero).one(df).toSeq("r", float) == @[1.0, 3.0]
    expect ValueError: discard col("w").round(-1)

suite "aggregations":
  proc four(): DataFrame = newDataFrame(series("a", [1, 2, 3, 4]))

  test "median, quantile, var, std":
    check col("a").median.one(four()).toSeq("r", float) == @[2.5]
    check col("a").quantile(0.25, interpolation = Linear).one(four()).toSeq("r", float) == @[1.75]
    check col("a").quantile(0.25, Lower).one(four()).toSeq("r", float) == @[1.0]
    check abs(col("a").var.one(four()).toSeq("r", float)[0] - 1.6666666) < 1e-6
    check col("a").var(ddof = 0).one(four()).toSeq("r", float) == @[1.25]
    check abs(col("a").std.one(four()).toSeq("r", float)[0] - 1.2909944) < 1e-6

  test "len vs count":
    let df = newDataFrame(series("a", [some(1), none(int), some(3)]))
    check df.select(col("a").len.alias("n"), col("a").count.alias("c")).toSeq("n", int) == @[3]
    check df.select(col("a").count.alias("c")).toSeq("c", int) == @[2]

suite "fill strategies":
  proc gaps(): DataFrame = newDataFrame(series("a", [some(1), none(int), none(int), some(4)]))

  test "forward and backward with limits":
    check col("a").forwardFill.one(gaps()).toSeq("r", int) == @[1, 1, 1, 4]
    check col("a").forwardFill(1).one(gaps()).toSeq("r", Option[int]) ==
      @[some(1), some(1), none(int), some(4)]
    check col("a").backwardFill.one(gaps()).toSeq("r", int) == @[1, 4, 4, 4]
    check col("a").fillNull(Forward).one(gaps()).toSeq("r", int) == @[1, 1, 1, 4]
    check col("a").fillNull(strategy = Backward, limit = 1).one(gaps()).toSeq("r", Option[int]) ==
      @[some(1), none(int), some(4), some(4)]

  test "mean, min, max, zero, one":
    let df = newDataFrame(series("a", [some(1), none(int), some(3)]))
    check col("a").fillNull(Mean).one(df).toSeq("r", float) == @[1.0, 2.0, 3.0]
    check col("a").fillNull(Min).one(df).toSeq("r", int) == @[1, 1, 3]
    check col("a").fillNull(Max).one(df).toSeq("r", int) == @[1, 3, 3]
    check col("a").fillNull(Zero).one(df).toSeq("r", int) == @[1, 0, 3]
    check col("a").fillNull(One).one(df).toSeq("r", int) == @[1, 1, 3]
    check col("a").fillNull(0).one(df).toSeq("r", int) == @[1, 0, 3]   # value form unchanged

suite "windows":
  test "group mean per row":
    let df = newDataFrame(series("g", ["x", "x", "y"]), series("v", [1, 3, 10]))
    check col("v").mean.over("g").one(df).toSeq("r", float) == @[2.0, 2.0, 10.0]
    check col("v").sum.over(["g"]).one(df).toSeq("r", int) == @[4, 4, 10]
    check col("v").max.over([col("g")]).one(df).toSeq("r", int) == @[3, 3, 10]

  test "forward fill within groups":
    let df = newDataFrame(series("g", ["x", "x", "y", "y"]),
                          series("r", [some("ana"), none(string), none(string), some("bo")]))
    check col("r").forwardFill.one(df).toSeq("r", Option[string]) ==
      @[some("ana"), some("ana"), some("ana"), some("bo")]
    check col("r").forwardFill.over("g").one(df).toSeq("r", Option[string]) ==
      @[some("ana"), some("ana"), none(string), some("bo")]
