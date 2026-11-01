import std/[unittest, options, math, tables]
import nanuq

suite "book needs (0.6)":
  let df = newDataFrame(series("brand", @["A", "B", "A", "C", "B"]),
                        series("price", @[10.0, 20.0, 30.0, NaN, 50.0]),
                        series("n", [some(1), some(2), none(int), some(4), some(5)]))

  test "frame aggregations":
    let s = df.select("brand", "n").sum
    check s.toList("n", int) == @[12]
    check s.toList("brand", Option[string]) == @[none(string)]
    check df.select("n").mean.toList("n", float) == @[3.0]
    check df.select("brand").max.toList("brand", string) == @["C"]
    check df.nUnique.toList("brand", int) == @[3]
    check df.count.toList("n", int) == @[4]
    check df.nullCount.toList("n", int) == @[1]
    check df.select("n").std.toList("n", float)[0] > 0
    check df.select("n").quantile(0.5).toList("n", float) == @[4.0]
    check df.lazy.select("n").median.collect.toList("n", float) == @[3.0]
    check df.select("n").`var`.height == 1

  test "fillNan on frames":
    let f = df.fillNan(0.0)
    check f.toList("price", float) == @[10.0, 20.0, 30.0, 0.0, 50.0]
    check df.fillNan(nil).toList("price", Option[float])[3].isNone

  test "group-by shortcuts":
    let g = df.groupBy("brand")
    check g.len.toList("len", int) == @[2, 2, 1]
    check g.count.columns == @["brand", "count"]
    check g.sum.toList("n", int) == @[1, 7, 4]
    check g.max.toList("price", float)[1] == 50.0
    check g.first.toList("price", float)[0] == 10.0
    check g.nUnique.columns == @["brand", "price", "n"]
    check g.head(1).toList("price", float)[0..1] == @[10.0, 20.0]
    check g.tail(1).height == 3
    check g.all.dtype("price") == List(Float64)
    check g.quantile(0.5).height == 3
    check df.lazy.groupBy("brand").mean.collect.height == 3

  test "iterating groups":
    var keys: seq[string]
    var rows: seq[int]
    for key, part in df.groupBy("brand"):
      keys.add key[0]
      rows.add part.height
    check keys == @["A", "B", "C"]
    check rows == @[2, 2, 1]

  test "select without a frame":
    let r = select(lit(1).alias("one"), intRange(0, 3).alias("i"))
    check r.toList("i", int) == @[0, 1, 2]
    check r.toList("one", int) == @[1, 1, 1]
