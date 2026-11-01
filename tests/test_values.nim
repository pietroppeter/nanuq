import std/[unittest, options]
import nanuq

proc ints(xs: openArray[int]): DataFrame = newDataFrame(series("x", xs))
proc one(e: Expr, df: DataFrame): DataFrame = df.select(e.alias("r"))

suite "ordering":
  test "sort and argSort":
    check col("x").sort(descending = true).one(ints([2, 3, 1])).toList("r", int) == @[3, 2, 1]
    check col("x").argSort.one(ints([2, 3, 1])).toList("r", int) == @[2, 0, 1]
  test "sortBy in agg":
    let df = newDataFrame(series("g", ["a", "a", "b", "b"]), series("s", ["p", "q", "r", "t"]),
                          series("w", [1, 5, 9, 2]))
    let r = df.groupBy(col("g")).agg(col("s").sortBy(col("w"), descending = true).first
      .alias("top")).sort("g").collect
    check r.toList("top", string) == @["q", "r"]
    check col("s").sortBy([col("g"), col("w")], [true, false]).one(df).toList("r", string) ==
      @["t", "r", "p", "q"]
  test "reverse":
    check col("x").reverse.one(ints([1, 2, 3])).toList("r", int) == @[3, 2, 1]

suite "picking values":
  let df = ints([10, 20, 30, 40])
  test "head, tail, slice":
    check col("x").head(2).one(df).toList("r", int) == @[10, 20]
    check col("x").tail(1).one(df).toList("r", int) == @[40]
    check col("x").slice(1, 2).one(df).toList("r", int) == @[20, 30]
    check col("x").slice(2).one(df).toList("r", int) == @[30, 40]
  test "gather":
    check col("x").gather([0, 2]).one(df).toList("r", int) == @[10, 30]
    check col("x").gather(3).one(df).toList("r", int) == @[40]
    check col("x").gatherEvery(2, 1).one(df).toList("r", int) == @[20, 40]
  test "topK and bottomK":
    check col("x").topK(2).one(df).toList("r", int) == @[40, 30]
    check col("x").bottomK(2).one(df).toList("r", int) == @[10, 20]
    let f = newDataFrame(series("y", [1982, 1997, 2015]), series("o", [2.2, 2.4, 2.6]))
    check f.select(col("y").topKBy("o", k = 2)).toList("y", int) == @[2015, 1997]
    check f.select(col("y").bottomKBy(col("o"), k = 1)).toList("y", int) == @[1982]
  test "indexOf and searchSorted":
    check col("x").indexOf(30).one(df).toList("r", int) == @[2]
    check col("x").indexOf(31).one(df).toList("r", Option[int]) == @[none(int)]
    let s = ints([1, 2, 2, 3])
    check col("x").searchSorted(2, SearchSortedSide.Left).one(s).toList("r", int) == @[1]
    check col("x").searchSorted(2, SearchSortedSide.Right).one(s).toList("r", int) == @[3]

suite "distinct values":
  let df = newDataFrame(series("x", ["b", "a", "b", "c"]))
  test "unique":
    check col("x").unique(maintainOrder = true).one(df).toList("r", string) == @["b", "a", "c"]
    check col("x").unique.one(df).sort("r").toList("r", string) == @["a", "b", "c"]
  test "flags":
    check col("x").isUnique.one(df).toList("r", bool) == @[false, true, false, true]
    check col("x").isDuplicated.one(df).toList("r", bool) == @[true, false, true, false]
    check col("x").isFirstDistinct.one(df).toList("r", bool) == @[true, true, false, true]
    check col("x").isLastDistinct.one(df).toList("r", bool) == @[false, true, true, true]
  test "counts":
    check col("x").argUnique.one(df).toList("r", int) == @[0, 1, 3]
    check col("x").uniqueCounts.one(df).toList("r", int) == @[2, 1, 1]
    check col("x").approxNUnique.one(df).toList("r", int) == @[3]

suite "recoding":
  test "replace keeps other values":
    let df = newDataFrame(series("x", ["N", "EN", "LN"]))
    check col("x").replace({"EN": "El Niño"}).one(df).toList("r", string) ==
      @["N", "El Niño", "LN"]
    check col("x").replace("N", "neutral").one(df).toList("r", string) == @["neutral", "EN", "LN"]
    check col("x").replace(["EN", "LN"], ["warm", "cold"]).one(df).toList("r", string) ==
      @["N", "warm", "cold"]
  test "replace keeps the dtype":
    let r = col("x").replace([1, 2], [10, 20]).one(ints([1, 2, 3]))
    check r.toList("r", int) == @[10, 20, 3]
  test "replaceStrict":
    let df = newDataFrame(series("x", ["a", "b"]))
    check col("x").replaceStrict({"a": 1, "b": 2}).one(df).toList("r", int) == @[1, 2]
    check col("x").replaceStrict({"a": 1}, default = 0).one(df).toList("r", int) == @[1, 0]
    expect InvalidOperationError:
      discard col("x").replaceStrict({"a": 1}).one(df)
  test "unequal lists":
    expect ValueError: discard col("x").replace([1, 2], [10])

suite "binning":
  test "cut with labels":
    let df = newDataFrame(series("x", [-1.6, -0.2, 0.9]))
    let r = col("x").cut([-0.5, 0.5], labels = ["cold", "neutral", "warm"]).one(df)
    check r.schema["r"].kind == DataTypeKind.Enum
    check r.toList("r", string) == @["cold", "neutral", "warm"]
  test "default labels":
    let r = col("x").cut([0.0]).one(newDataFrame(series("x", [-1.0, 1.0])))
    check r.toList("r", string) == @["(-inf, 0]", "(0, inf]"]
  test "qcut":
    let df = ints([1, 2, 3, 4])
    check col("x").qcut(2, labels = ["low", "high"]).one(df).toList("r", string) ==
      @["low", "low", "high", "high"]
    check col("x").qcut([0.5], labels = ["low", "high"]).one(df).toList("r", string) ==
      @["low", "low", "high", "high"]
  test "label count":
    expect ValueError: discard col("x").cut([0.0], labels = ["one"])

suite "value counts":
  let df = newDataFrame(series("p", ["n", "w", "n", "c", "n", "w"]))
  test "sorted counts":
    let r = df.valueCounts("p", sort = true)
    check r.columns == @["p", "count"]
    check r.toList("p", string) == @["n", "w", "c"]
    check r.toList("count", int) == @[3, 2, 1]
  test "normalize and lazy":
    let r = newDataFrame(series("x", ["a", "a", "b", "b"])).lazy
      .valueCounts(col("x"), normalize = true).collect.sort("x")
    check r.columns == @["x", "proportion"]
    check r.toList("proportion", float) == @[0.5, 0.5]
