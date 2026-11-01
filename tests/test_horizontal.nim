import std/[unittest, options, math]
import nanuq

suite "horizontal functions":
  let df = newDataFrame(series("a", [some(1.0), some(4.0), none(float)]),
                        series("b", [2.0, 30.0, 61.0]), series("s", ["x", "y", "z"]))
  test "sum with selector, nulls skipped":
    check df.select(sumHorizontal(col(float)).alias("r")).toList("r", float) == @[3.0, 34.0, 61.0]
  test "sum keeping nulls":
    check df.select(sumHorizontal([col("a"), col("b")], ignoreNulls = false).alias("r"))
      .toList("r", Option[float]) == @[some(3.0), some(34.0), none(float)]
  test "names, literals, mean, min, max":
    check df.select(maxHorizontal(["a", "b"]).alias("r")).toList("r", float) == @[2.0, 30.0, 61.0]
    check df.select(minHorizontal(col("b"), 10.0).alias("r")).toList("r", float) == @[2.0, 10.0, 10.0]
    check df.select(meanHorizontal(col("a"), col("b")).alias("r")).toList("r", float) ==
      @[1.5, 17.0, 61.0]
  test "all and any":
    let b = newDataFrame(series("p", [true, true]), series("q", [false, true]))
    check b.select(allHorizontal(col("p"), col("q")).alias("r")).toList("r", bool) == @[false, true]
    check b.select(anyHorizontal(col("p"), col("q")).alias("r")).toList("r", bool) == @[true, true]
  test "coalesce":
    check df.select(coalesce(col("a"), col("b")).alias("r")).toList("r", float) == @[1.0, 4.0, 61.0]
    check df.select(coalesce(col("a"), 0.0).alias("r")).toList("r", float) == @[1.0, 4.0, 0.0]

suite "generated columns":
  test "intRange":
    check newDataFrame().select(intRange(1950, 2026, 25).alias("y")).toList("y", int) ==
      @[1950, 1975, 2000, 2025]
    check newDataFrame().select(intRange(3).alias("y")).toList("y", int) == @[0, 1, 2]
    let df = newDataFrame(series("x", ["a", "b"]))
    check df.withColumns(intRange(0, col("x").len, dtype = UInt32).alias("i"))
      .toList("i", int) == @[0, 1]
    expect ValueError: discard intRange(0, 5, step = 0)
  test "linearSpace and repeat":
    check newDataFrame().select(linearSpace(0, 1, 5).alias("v")).toList("v", float) ==
      @[0.0, 0.25, 0.5, 0.75, 1.0]
    check newDataFrame().select(repeat(lit("x"), 3).alias("v")).toList("v", string) == @["x", "x", "x"]

suite "correlation":
  test "pearson, spearman, cov":
    let df = newDataFrame(series("a", [1.0, 2.0, 3.0]), series("b", [2.0, 4.0, 7.0]))
    check abs(df.select(corr("a", "b").alias("r")).toList("r", float)[0] - 0.9933992677987828) < 1e-12
    check df.select(corr(col("a"), col("b"), Spearman).alias("r")).toList("r", float) == @[1.0]
    check df.select(cov("a", "b").alias("r")).toList("r", float) == @[2.5]
