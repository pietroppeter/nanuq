import std/[unittest, options]
import nanuq

proc nums(): DataFrame =
  newDataFrame(series("a", [1, 2, 3, 4, 5]), series("b", ["p", "q", "r", "s", "t"]))

suite "columns":
  test "drop":
    let df = newDataFrame(series("a", [1]), series("b", [2]), series("c", [3]))
    check df.drop("b").columns == @["a", "c"]
    check df.drop(["a", "c"]).columns == @["b"]
    check df.lazy.drop("a").collect.columns == @["b", "c"]
    check df.drop(["zzz", "a"], strict = false).columns == @["b", "c"]

  test "rename":
    check nums().rename({"a": "x"}).columns == @["x", "b"]
    check nums().rename({"a": "b", "b": "a"}).toList("b", int) == @[1, 2, 3, 4, 5]

  test "strict":
    expect PolarsError: discard nums().drop("zzz")
    check nums().drop("zzz", strict = false).columns == @["a", "b"]
    expect PolarsError: discard nums().rename({"zzz": "y"})
    check nums().rename({"zzz": "y"}, strict = false).columns == @["a", "b"]

suite "row windows":
  test "head and tail":
    check nums().tail(2).toList("a", int) == @[4, 5]
    check nums().tail.height == 5
    check nums().tail(10).height == 5
    check nums().lazy.head(2).collect.toList("a", int) == @[1, 2]
    check nums().lazy.tail(1).collect.toList("a", int) == @[5]

  test "slice":
    check nums().slice(1, 2).toList("a", int) == @[2, 3]
    check nums().slice(-3, 2).toList("a", int) == @[3, 4]
    check nums().slice(1).toList("a", int) == @[2, 3, 4, 5]
    check nums().slice(-2).toList("a", int) == @[4, 5]
    check nums().slice(10).height == 0
    expect ValueError: discard nums().slice(0, -1)

  test "reverse":
    check nums().reverse.toList("b", string) == @["t", "s", "r", "q", "p"]

suite "unique":
  proc dups(): DataFrame =
    newDataFrame(series("k", ["a", "b", "a"]), series("v", [1, 2, 3]))

  test "keep strategies":
    let first = dups().unique("k", keep = First, maintainOrder = true)
    check first.toList("k", string) == @["a", "b"]
    check first.toList("v", int) == @[1, 2]
    let last = dups().unique("k", keep = Last, maintainOrder = true)
    check last.toList("v", int) == @[2, 3]
    check dups().unique("k", keep = None).toList("v", int) == @[2]
    check dups().unique("k").height == 2
    check dups().unique(["k"], keep = First, maintainOrder = true).toList("v", int) == @[1, 2]

  test "all columns":
    let df = newDataFrame(series("x", [1, 1, 2]), series("y", ["a", "a", "a"]))
    check df.unique(maintainOrder = true).toList("x", int) == @[1, 2]
    check dups().unique.height == 3

suite "row index":
  test "default and offset":
    let df = nums().withRowIndex
    check df.columns == @["index", "a", "b"]
    check df.toList("index", int) == @[0, 1, 2, 3, 4]
    check nums().head(3).withRowIndex("n", offset = 1).toList("n", int) == @[1, 2, 3]
    check $nums().withRowIndex.dtype("index") == "u32"
    expect ValueError: discard nums().withRowIndex(offset = -1)

suite "sorting":
  proc groups(): DataFrame =
    newDataFrame(series("g", ["y", "x", "y", "x"]), series("v", [1, 2, 3, 4]))

  test "two keys":
    let s = groups().sort(["g", "v"], descending = [false, true])
    check s.toList("g", string) == @["x", "x", "y", "y"]
    check s.toList("v", int) == @[4, 2, 3, 1]

  test "one value applies to every key":
    check groups().sort(["g", "v"], descending = [true]).toList("v", int) == @[3, 1, 4, 2]

  test "expression keys":
    check groups().sort([col("v") * -1]).toList("v", int) == @[4, 3, 2, 1]

  test "nulls last":
    let df = newDataFrame(series("a", [none(int), some(2), some(1)]))
    check df.sort("a").toList("a", Option[int]) == @[none(int), some(1), some(2)]
    check df.sort("a", nullsLast = true).toList("a", Option[int]) == @[some(1), some(2), none(int)]
    check df.sort(["a"], nullsLast = [true]).toList("a", Option[int]) ==
      @[some(1), some(2), none(int)]

  test "maintainOrder keeps ties in place":
    let s = groups().sort("g", maintainOrder = true)
    check s.toList("v", int) == @[2, 4, 1, 3]

  test "length mismatch and no keys":
    let df = newDataFrame(series("a", [1]), series("b", [1]), series("c", [1]))
    expect PolarsError: discard df.sort(["a", "b", "c"], descending = [true, false])
    expect PolarsError: discard df.sort(newSeq[string]())

  test "lazy":
    check groups().lazy.sort(["g", "v"]).collect.toList("v", int) == @[2, 4, 1, 3]

suite "sample":
  proc ten(): DataFrame =
    var xs: seq[int]
    for i in 0 ..< 10: xs.add i
    newDataFrame(series("x", xs))

  test "seeded samples repeat":
    let a = ten().sample(3, seed = some(42))
    let b = ten().sample(3, seed = some(42))
    check a.height == 3
    check a.toList("x", int) == b.toList("x", int)

  test "plain int seed and the global seed":
    check ten().sample(3, seed = 7).toList("x", int) == ten().sample(3, seed = some(7)).toList("x", int)
    check ten().sample(fraction = 0.5, seed = 7).height == 5
    setRandomSeed(42)
    let a = ten().sample(4).toList("x", int)
    setRandomSeed(42)
    check ten().sample(4).toList("x", int) == a
    expect ValueError: setRandomSeed(-1)

  test "fraction":
    check ten().sample(fraction = 0.5).height == 5
    check ten().sample(fraction = 2.0, withReplacement = true).height == 20

  test "too many rows and bad arguments":
    expect PolarsError: discard ten().sample(11)
    check ten().sample(11, withReplacement = true).height == 11
    expect ValueError: discard ten().sample(-1)
    expect ValueError: discard ten().sample(1, seed = some(-1))

  test "shuffle keeps all rows":
    let s = ten().sample(10, shuffle = true, seed = some(1))
    check s.height == 10
    check s.sort("x").toList("x", int) == ten().toList("x", int)

suite "option values":
  test "UniqueKeepStrategy.None and MaintainOrderJoin.None coexist":
    check compiles(newDataFrame(series("k", [1])).unique("k", keep = None))
    check UniqueKeepStrategy.None != UniqueKeepStrategy.Any

suite "gatherEvery and groupBy by name":
  test "gatherEvery":
    let df = newDataFrame(series("m", [1, 2, 3, 4, 5, 6]))
    check df.gatherEvery(3, offset = 2).toList("m", int) == @[3, 6]
    check df.lazy.gatherEvery(2).collect.toList("m", int) == @[1, 3, 5]
    check df.gatherEvery(2, offset = 10).height == 0
  test "groupBy names":
    let df = newDataFrame:
      a: ["x", "y", "x"]
      v: [1, 2, 3]
    check df.groupBy("a").agg(col.v.sum).toList("v", int) == @[4, 2]
