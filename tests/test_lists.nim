import std/[unittest, options]
import nanuq

suite "list namespace":
  let df = newDataFrame:
    cubs: [@[2, 1, 3], @[], @[4]]
    names: [@["Ada", "Bo"], @["Cy"], @[]]

  test "aggregations and access":
    let r = df.select(col("cubs").list.len.alias("n"), col("cubs").list.sum.alias("sum"),
                      col("cubs").list.max.alias("max"),
                      col("cubs").list.get(0, nullOnOob = true).alias("first"),
                      col("cubs").list.get(-1, nullOnOob = true).alias("last"),
                      col("cubs").list.contains(3).alias("has3"),
                      col("names").list.join(", ").alias("names"))
    check r.toList("n", int) == @[3, 0, 1]
    check r.toList("sum", int) == @[6, 0, 4]
    check r.toList("max", Option[int]) == @[some(3), none(int), some(4)]
    check r.toList("first", Option[int]) == @[some(2), none(int), some(4)]
    check r.toList("last", Option[int]) == @[some(3), none(int), some(4)]
    check r.toList("has3", bool) == @[true, false, false]
    check r.toList("names", string) == @["Ada, Bo", "Cy", ""]
    expect PolarsError:
      discard df.select(col("cubs").list.get(5))

  test "slices":
    let r = df.select(col("cubs").list.head(2).alias("h"), col("cubs").list.slice(1).alias("s"),
                      col("cubs").list.gather([0, 0], nullOnOob = true).alias("g"))
    check r.toList("h", seq[int]) == @[@[2, 1], @[], @[4]]
    check r.toList("s", seq[int]) == @[@[1, 3], @[], @[]]

  test "transforms":
    let d = newDataFrame:
      a: [@[3, 1, 3], @[2]]
      b: [@[1, 5], @[2, 4]]
    let r = d.select(col("a").list.sort.alias("sorted"),
                     col("a").list.unique(maintainOrder = true).alias("unique"),
                     col("a").list.union(col("b")).alias("union"),
                     col("a").list.setIntersection(col("b")).alias("inter"),
                     col("a").list.filter(element() > 1).alias("gt1"),
                     col("a").list.reverse.alias("rev"))
    check r.toList("sorted", seq[int]) == @[@[1, 3, 3], @[2]]
    check r.toList("unique", seq[int]) == @[@[3, 1], @[2]]
    check r.toList("union", seq[int]) == @[@[3, 1, 5], @[2, 4]]
    check r.toList("inter", seq[int]) == @[@[1], @[2]]
    check r.toList("gt1", seq[int]) == @[@[3, 3], @[2]]
    check r.toList("rev", seq[int]) == @[@[3, 1, 3], @[2]]
    let s = d.select(col("b").list.toStruct(["x", "y"]).alias("p"))
    check s.toList("p", tuple[x, y: int]) == @[(x: 1, y: 5), (x: 2, y: 4)]
    check d.select(col("b").list.toArray(2)).dtype("b") == Array(Int64, 2)

  test "eval and agg":
    let w = newDataFrame:
      weights: [@[410.0, 380.0], @[450.0, 470.0, 455.0]]
    let r = w.select(col("weights").list.eval(element().rank).alias("rank"),
                     col("weights").list.agg(element().max - element().min).alias("spread"))
    check r.toList("rank", seq[float]) == @[@[2.0, 1.0], @[1.0, 3.0, 2.0]]
    check r.toList("spread", float) == @[30.0, 20.0]

  test "explode, implode, concatList":
    let f = newDataFrame:
      den: ["A", "B", "C"]
      cubs: [@["Ada", "Bo"], @[], @["Cy"]]
    let e = f.explode("cubs")
    check e.toList("den", string) == @["A", "A", "B", "C"]
    check e.toList("cubs", Option[string]) == @[some("Ada"), some("Bo"), none(string), some("Cy")]
    check f.explode("cubs", emptyAsNull = false).height == 3
    check f.select(col("cubs").explode).height == 4
    let c = f.select(concatList(col("den"), col("cubs")).alias("all"))
    check c.toList("all", seq[string]) == @[@["A", "Ada", "Bo"], @["B"], @["C", "Cy"]]
    check f.select(col("den").implode).toList("den", seq[string]) == @[@["A", "B", "C"]]
    check f.lazy.explode("cubs").collect.height == 4

suite "repeatBy and seeds":
  test "repeatBy":
    let df = newDataFrame:
      a: ["x", "y"]
      n: [2, 1]
    let r = df.select(col("a").repeatBy("n"), col("a").repeatBy(2).alias("two"))
    check r.toList("a", seq[string]) == @[@["x", "x"], @["y"]]
    check r.toList("two", seq[string]) == @[@["x", "x"], @["y", "y"]]
  test "sample with an int seed":
    let df = newDataFrame:
      m: [4806, 4634, 4061, 4506, 4478]
      l: [@[1, 2, 3], @[4, 5], @[6], @[7, 8], @[9]]
    let a = df.select(col("m").sample(3, seed = 42)).toList("m", int)
    check a == df.select(col("m").sample(3, seed = 42)).toList("m", int)
    check df.select(col("l").list.sample(1, seed = 7)).height == 5
