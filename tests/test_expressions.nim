import std/[unittest, options, math]
import nanuq

proc weights(): DataFrame = newDataFrame(series("w", [100, 300, 900]))
proc one(e: Expr, df: DataFrame): DataFrame = df.select(e.alias("r"))

suite "conditionals":
  test "three-way chain":
    let size = `when`(col("w") < 150).then("cub").when(col("w") < 500).then("adult").otherwise("chonk")
    check size.one(weights()).toList("r", string) == @["cub", "adult", "chonk"]

  test "no otherwise gives null":
    let r = weights().select(`when`(col("w") < 150).then(1).alias("r"))
    check r.toList("r", Option[int]) == @[some(1), none(int), none(int)]

  test "expression values and string literals":
    let r = `when`(col("w") > 200).then(col("w") * 2).otherwise(0).one(weights())
    check r.toList("r", int) == @[0, 600, 1800]
    # a string is a value, not a column name
    let s = `when`(col("w") > 200).then("w").otherwise("light").one(weights())
    check s.toList("r", string) == @["light", "w", "w"]

  test "choose builds the same plan":
    let chain = `when`(col("w") < 150).then("cub").when(col("w") < 500).then("adult").otherwise("chonk")
    let macroed = choose:
      if col("w") < 150: "cub"
      elif col("w") < 500: "adult"
      else: "chonk"
    check $macroed == $chain
    check macroed.one(weights()).toList("r", string) == @["cub", "adult", "chonk"]

  test "choose on one line and without else":
    let df = newDataFrame(series("collared", [true, false]))
    let r = df.select(choose(if col("collared"): "tracked" else: "free").alias("status"))
    check r.toList("status", string) == @["tracked", "free"]
    let noElse = choose:
      if col("w") < 150: "cub"
    check noElse.one(weights()).toList("r", Option[string]) == @[some("cub"), none(string), none(string)]

  test "choose rejects other bodies":
    check not compiles(choose(col("w") + 1))

suite "membership and ranges":
  proc abc(): DataFrame = newDataFrame(series("a", [1, 2, 3]))

  test "isIn":
    check col("a").isIn([1, 3]).one(abc()).toList("r", bool) == @[true, false, true]
    let s = newDataFrame(series("s", ["x", "y"]))
    check s.select(col("s").isIn(["y"]).alias("r")).toList("r", bool) == @[false, true]

  test "isIn with nulls":
    let df = newDataFrame(series("a", [some(1), none(int)]), series("b", [some(1), none(int)]))
    check df.select(col("a").isIn([1]).alias("r")).toList("r", Option[bool])[0] == some(true)

  test "isBetween":
    check col("a").isBetween(1, 3).one(abc()).toList("r", bool) == @[true, true, true]
    check col("a").isBetween(1, 3, closed = Left).one(abc()).toList("r", bool) == @[true, true, false]
    check col("a").isBetween(1, 3, closed = None).one(abc()).toList("r", bool) == @[false, true, false]

suite "arithmetic":
  test "floor semantics of mod and div":
    let df = newDataFrame(series("a", [-7, 7]))
    check (col("a") mod 3).one(df).toList("r", int) == @[2, 1]
    check (col("a") div 3).one(df).toList("r", int) == @[-3, 2]

  test "power, abs, negation":
    let df = newDataFrame(series("a", [-3, 2]))
    check (col("a") ^ 2).one(df).toList("r", float) == @[9.0, 4.0]
    check col("a").pow(3).one(df).toList("r", float) == @[-27.0, 8.0]
    check (2 ^ col("a")).one(newDataFrame(series("a", [3]))).toList("r", float) == @[8.0]
    check col("a").abs.one(df).toList("r", int) == @[3, 2]
    check (-col("a")).one(df).toList("r", int) == @[3, -2]

  test "round":
    let df = newDataFrame(series("w", [1.23456, 2.5]))
    check col("w").round(2).one(df).toList("r", float) == @[1.23, 2.5]
    check col("w").round.one(df).toList("r", float) == @[1.0, 2.0]
    check col("w").round(mode = HalfAwayFromZero).one(df).toList("r", float) == @[1.0, 3.0]
    expect ValueError: discard col("w").round(-1)

suite "aggregations":
  proc four(): DataFrame = newDataFrame(series("a", [1, 2, 3, 4]))

  test "median, quantile, var, std":
    check col("a").median.one(four()).toList("r", float) == @[2.5]
    check col("a").quantile(0.25, interpolation = Linear).one(four()).toList("r", float) == @[1.75]
    check col("a").quantile(0.25, Lower).one(four()).toList("r", float) == @[1.0]
    check abs(col("a").var.one(four()).toList("r", float)[0] - 1.6666666) < 1e-6
    check col("a").var(ddof = 0).one(four()).toList("r", float) == @[1.25]
    check abs(col("a").std.one(four()).toList("r", float)[0] - 1.2909944) < 1e-6

  test "len vs count":
    let df = newDataFrame(series("a", [some(1), none(int), some(3)]))
    check df.select(col("a").len.alias("n"), col("a").count.alias("c")).toList("n", int) == @[3]
    check df.select(col("a").count.alias("c")).toList("c", int) == @[2]

suite "fill strategies":
  proc gaps(): DataFrame = newDataFrame(series("a", [some(1), none(int), none(int), some(4)]))

  test "forward and backward with limits":
    check col("a").forwardFill.one(gaps()).toList("r", int) == @[1, 1, 1, 4]
    check col("a").forwardFill(1).one(gaps()).toList("r", Option[int]) ==
      @[some(1), some(1), none(int), some(4)]
    check col("a").backwardFill.one(gaps()).toList("r", int) == @[1, 4, 4, 4]
    check col("a").fillNull(Forward).one(gaps()).toList("r", int) == @[1, 1, 1, 4]
    check col("a").fillNull(strategy = Backward, limit = 1).one(gaps()).toList("r", Option[int]) ==
      @[some(1), none(int), some(4), some(4)]

  test "mean, min, max, zero, one":
    let df = newDataFrame(series("a", [some(1), none(int), some(3)]))
    check col("a").fillNull(Mean).one(df).toList("r", float) == @[1.0, 2.0, 3.0]
    check col("a").fillNull(Min).one(df).toList("r", int) == @[1, 1, 3]
    check col("a").fillNull(Max).one(df).toList("r", int) == @[1, 3, 3]
    check col("a").fillNull(Zero).one(df).toList("r", int) == @[1, 0, 3]
    check col("a").fillNull(One).one(df).toList("r", int) == @[1, 1, 3]
    check col("a").fillNull(0).one(df).toList("r", int) == @[1, 0, 3]   # value form unchanged

suite "windows":
  test "group mean per row":
    let df = newDataFrame(series("g", ["x", "x", "y"]), series("v", [1, 3, 10]))
    check col("v").mean.over("g").one(df).toList("r", float) == @[2.0, 2.0, 10.0]
    check col("v").sum.over(["g"]).one(df).toList("r", int) == @[4, 4, 10]
    check col("v").max.over([col("g")]).one(df).toList("r", int) == @[3, 3, 10]

  test "forward fill within groups":
    let df = newDataFrame(series("g", ["x", "x", "y", "y"]),
                          series("r", [some("ana"), none(string), none(string), some("bo")]))
    check col("r").forwardFill.one(df).toList("r", Option[string]) ==
      @[some("ana"), some("ana"), some("ana"), some("bo")]
    check col("r").forwardFill.over("g").one(df).toList("r", Option[string]) ==
      @[some("ana"), some("ana"), none(string), some("bo")]

suite "true division":
  test "integers divide to floats":
    let df = newDataFrame(series("a", [7, 1, 0]))
    let r = df.select((col.a / 2).alias("h"), (col.a div 2).alias("w"))
    check r.dtype("h") == Float64
    check r.toList("h", float) == @[3.5, 0.5, 0.0]
    check r.dtype("w") == Int64
    check r.toList("w", int) == @[3, 0, 0]

  test "division by zero":
    let df = newDataFrame(series("a", [1, 0]))
    let v = df.select((col.a / 0).alias("z")).toList("z", float)
    check v[0] == Inf
    check v[1].isNaN

suite "nullCount and rank":
  test "nullCount as an aggregation":
    let df = newDataFrame(series("g", ["x", "x", "y"]),
                          series("a", [some(1), none(int), some(3)]))
    check df.select(col.a.nullCount).toList("a", int) == @[1]
    let per = df.groupBy(col.g).agg(col.a.nullCount).sort("g")
    check per.toList("a", int) == @[1, 0]

  test "rank methods":
    let df = newDataFrame(series("a", [9, 9, 7]))
    proc r(e: Expr): seq[float] = df.select(e.alias("r")).toList("r", float)
    check r(col.a.rank) == @[2.5, 2.5, 1.0]
    check df.select(col.a.rank.alias("r")).dtype("r") == Float64
    check r(col.a.rank(Min, descending = true)) == @[1.0, 1.0, 3.0]
    check df.select(col.a.rank(Min).alias("r")).dtype("r") == UInt32
    check r(col.a.rank(Max)) == @[3.0, 3.0, 1.0]
    check r(col.a.rank(Dense)) == @[2.0, 2.0, 1.0]
    check r(col.a.rank(RankMethod.Ordinal)) == @[2.0, 3.0, 1.0]
    check r(col.a.rank(RankMethod.Random, seed = 1)) == r(col.a.rank(RankMethod.Random, seed = 1))

  test "rank keeps nulls":
    let df = newDataFrame(series("a", [some(2), none(int), some(1)]))
    check df.select(col.a.rank(Min)).toList("a", Option[int]) == @[some(2), none(int), some(1)]

suite "filter inside expressions":
  test "conditional aggregation":
    let df = newDataFrame:
      rider: ["a", "a", "b", "b"]
      kind: ["TT", "road", "TT", "TT"]
      pts: [10, 5, 3, 4]
    let r = df.groupBy(col.rider).agg(col.pts.filter(col.kind == "TT").sum.alias("tt"),
                                      col.pts.sum.alias("all")).sort("rider")
    check r.toList("tt", int) == @[10, 7]
    check r.toList("all", int) == @[15, 7]
    check df.select(col.pts.filter(col.pts > 4)).toList("pts", int) == @[10, 5]

suite "boolean aggregations":
  test "any and all":
    let df = newDataFrame:
      g: ["a", "a", "b"]
      w: [true, false, true]
    let r = df.groupBy("g").agg(col.w.all.alias("all"), col.w.any.alias("any"))
    check r.toList("all", bool) == @[false, true]
    check r.toList("any", bool) == @[true, true]
    let n = newDataFrame(series("w", [some(false), none(bool)]))
    check n.select(col.w.any(ignoreNulls = false)).toList("w", Option[bool]) == @[none(bool)]
    check n.select(col.w.any).toList("w", bool) == @[false]
    check df["w"].all.item(bool) == false
    check df.select(all()).width == 2
