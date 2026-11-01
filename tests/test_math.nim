import std/[unittest, options, math]
import nanuq

proc floats(xs: openArray[float]): DataFrame = newDataFrame(series("x", xs))
proc one(e: Expr, df: DataFrame): DataFrame = df.select(e.alias("r"))

suite "elementwise math":
  test "sqrt of integers is float":
    let r = col("x").sqrt.one(newDataFrame(series("x", [4, 9])))
    check r.schema["r"] == Float64
    check r.toList("r", float) == @[2.0, 3.0]

  test "cbrt, exp, logs":
    let df = floats([1.0, 8.0])
    check col("x").cbrt.one(df).toList("r", float) == @[1.0, 2.0]
    check col("x").log(2.0).one(df).toList("r", float) == @[0.0, 3.0]
    check col("x").log.one(df).toList("r", float)[0] == 0.0
    check col("x").log10.one(floats([100.0])).toList("r", float) == @[2.0]
    check col("x").log1p.one(floats([0.0])).toList("r", float) == @[0.0]
    check abs(col("x").exp.one(floats([1.0])).toList("r", float)[0] - E) < 1e-12

  test "sign, floor, ceil":
    let df = floats([-2.5, 1.5])
    check col("x").sign.one(df).toList("r", float) == @[-1.0, 1.0]
    check col("x").floor.one(df).toList("r", float) == @[-3.0, 1.0]
    check col("x").ceil.one(df).toList("r", float) == @[-2.0, 2.0]

  test "nulls stay null":
    let df = newDataFrame(series("x", [some(4.0), none(float)]))
    check col("x").sqrt.one(df).toList("r", Option[float]) == @[some(2.0), none(float)]

suite "clip":
  test "both bounds":
    check col("x").clip(-1.0, 1.0).one(floats([-2.1, 0.4, 2.6])).toList("r", float) ==
      @[-1.0, 0.4, 1.0]
  test "one bound, named":
    let df = floats([-2.0, 3.0])
    check col("x").clip(lowerBound = 0.0).one(df).toList("r", float) == @[0.0, 3.0]
    check col("x").clip(upperBound = 0.0).one(df).toList("r", float) == @[-2.0, 0.0]
  test "expression bounds":
    let df = newDataFrame(series("x", [5, 50]), series("hi", [10, 20]))
    check col("x").clip(0, col("hi")).one(df).toList("r", int) == @[5, 20]
  test "positional single bound does not compile":
    check not compiles(col("x").clip(0))

suite "trigonometry":
  test "radians and degrees":
    check col("x").radians.degrees.one(floats([90.0])).toList("r", float) == @[90.0]
  test "sin, cos, arctan2":
    let df = floats([0.0])
    check col("x").sin.one(df).toList("r", float) == @[0.0]
    check col("x").cos.one(df).toList("r", float) == @[1.0]
    let a = floats([1.0]).select(arctan2(col("x"), 1.0).degrees.alias("r"))
    check abs(a.toList("r", float)[0] - 45.0) < 1e-9
  test "inverse and hyperbolic":
    let df = floats([0.0])
    for e in [col("x").tan, col("x").arcsin, col("x").arctan, col("x").sinh,
              col("x").tanh, col("x").arcsinh, col("x").arctanh]:
      check e.one(df).toList("r", float) == @[0.0]
    check col("x").cosh.one(df).toList("r", float) == @[1.0]
    check col("x").arccosh.one(floats([1.0])).toList("r", float) == @[0.0]
    check abs(col("x").arccos.one(floats([1.0])).toList("r", float)[0]) < 1e-12
    check abs(col("x").cot.one(floats([PI / 4])).toList("r", float)[0] - 1.0) < 1e-12

suite "NaN and infinity":
  let df = newDataFrame(series("x", [some(1.0), some(NaN), some(Inf), none(float)]))
  test "tests":
    check col("x").isNan.one(df).toList("r", Option[bool]) ==
      @[some(false), some(true), some(false), none(bool)]
    check col("x").isNotNan.one(df).toList("r", Option[bool])[1] == some(false)
    check col("x").isFinite.one(df).toList("r", Option[bool]) ==
      @[some(true), some(false), some(false), none(bool)]
    check col("x").isInfinite.one(df).toList("r", Option[bool])[2] == some(true)
  test "NaN is not null":
    check col("x").isNull.one(df).toList("r", bool) == @[false, false, false, true]
  test "fillNan leaves nulls":
    check col("x").fillNan(0.0).one(df).toList("r", Option[float]) ==
      @[some(1.0), some(0.0), some(Inf), none(float)]
  test "drop":
    check df.select(col("x").dropNans.dropNulls).toList("x", float) == @[1.0, Inf]

suite "dot":
  test "integer columns":
    let df = newDataFrame(series("a", [1, 2, 3]), series("b", [4, 5, 6]))
    check df.select(col("a").dot(col("b"))).toList("a", int) == @[32]
