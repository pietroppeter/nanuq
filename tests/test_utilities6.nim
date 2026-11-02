import std/[unittest, options, os, strutils, times, sequtils]
import nanuq

suite "smaller functions (0.6)":
  test "method spellings and xor":
    let df = newDataFrame(series("a", @[6, 3]), series("b", @[true, false]))
    let r = df.select(col("a").mul(2).alias("m"), col("a").sub(1).alias("s"),
                      col("a").add(col("a")).alias("p"), col("a").truediv(4).alias("t"),
                      col("a").floordiv(4).alias("f"), col("a").gt(4).alias("g"),
                      col("a").neg.alias("n"), (col("a") xor 5).alias("x"),
                      (col("b") xor true).alias("bx"))
    check r.toList("m", int) == @[12, 6]
    check r.toList("s", int) == @[5, 2]
    check r.toList("p", int) == @[12, 6]
    check r.toList("t", float) == @[1.5, 0.75]
    check r.toList("f", int) == @[1, 0]
    check r.toList("g", bool) == @[true, false]
    check r.toList("n", int) == @[-6, -3]
    check r.toList("x", int) == @[3, 6]
    check r.toList("bx", bool) == @[false, true]

  test "ranges":
    let df = newDataFrame(series("lo", @[1, 3]), series("hi", @[3, 6]))
    let r = df.select(intRanges(col("lo"), col("hi")).alias("r"))
    check r.toList("r", seq[int]) == @[@[1, 2], @[3, 4, 5]]
    check newDataFrame().select(arange(0, 3).alias("a")).toList("a", int) == @[0, 1, 2]
    let d = newDataFrame(series("s", @[date(2024, 1, 1)]), series("e", @[date(2024, 1, 3)]))
    check d.select(dateRanges(col("s"), col("e")).alias("r")).toList("r", seq[Date])[0].len == 3
    check d.select(datetimeRanges(col("s").cast(dataType(DateTime)), col("e").cast(dataType(DateTime)),
                                  "1d").list.len.alias("n")).toList("n", int) == @[3]

  test "joinWhere":
    let east = newDataFrame(series("id", @[100, 101]), series("dur", @[140, 100]))
    let west = newDataFrame(series("t_id", @[404, 498]), series("time", @[90, 130]))
    let r = east.joinWhere(west, col("dur") < col("time")).sort("id")
    check r.height == 1
    check r.toList("id", int) == @[101]

  test "hist":
    let s = series("x", @[1.0, 2.0, 2.5, 4.0])
    let h = s.hist(bins = [0.0, 2.0, 4.0])
    check h.columns == @["breakpoint", "category", "count"]
    check h.toList("count", int) == @[2, 2]
    let c = newDataFrame(s).select(col("x").hist(binCount = 2))
    check c.height == 2

  test "frame helpers":
    var df = newDataFrame(series("a", @[1, 2]))
    df.append(newDataFrame(series("a", @[3])))
    check df.toList("a", int) == @[1, 2, 3]
    check df.remove(col("a") > 1).toList("a", int) == @[1]
    check series("a", @[1, 2, 3]).isSorted
    check not series("a", @[3, 1]).isSorted
    check series("a", @[3, 1]).isSorted(descending = true)
    check df.setSorted("a").height == 3
    check threadPoolSize() >= 1
    let e = explainAll([df.lazy.filter(col("a") > 1), df.lazy.select(col("a").sum)])
    check e.len > 0

  test "fromEpoch and parquet schema":
    let df = newDataFrame(series("ts", @[0, 86400]), series("d", @[0, 1]))
    let r = df.select(fromEpoch("ts").alias("t"), fromEpoch(col("d"), EpochUnit.Days).alias("day"))
    check r.toList("day", Date) == @[date(1970, 1, 1), date(1970, 1, 2)]
    check r.dtype("t").kind == DataTypeKind.Datetime
    let path = getTempDir() / "nanuq_schema.parquet"
    df.writeParquet(path)
    check readParquetSchema(path)["ts"] == Int64

  test "unstack":
    let df = newDataFrame(series("x", @["a", "b", "c", "d", "e"]), series("n", @[1, 2, 3, 4, 5]))
    let v = df.unstack(2, columns = ["x"])
    check v.columns == @["x_0", "x_1", "x_2"]
    check v.toList("x_0", string) == @["a", "b"]
    check v.toList("x_2", Option[string]) == @[some("e"), none(string)]
    let h = df.unstack(2, UnstackDirection.Horizontal, columns = ["n"], fillValues = lit(0))
    check h.columns == @["n_0", "n_1"]
    check h.toList("n_0", int) == @[1, 3, 5]
    check h.toList("n_1", int) == @[2, 4, 0]

  test "rollingMap":
    let df = newDataFrame(series("x", @[1.0, 2.0, 3.0, 4.0]))
    let r = df.select(col("x").rollingMap(proc (w: seq[float]): float = w.foldl(a + b), windowSize = 2))
    check r.toList("x", Option[float]) == @[none(float), some(3.0), some(5.0), some(7.0)]

  test "scatter and set":
    let s = series("x", @[1, 2, 3])
    check s.scatter([0, 2], [10, 30]).toList(int) == @[10, 2, 30]
    check s.scatter([-1], 9).toList(int) == @[1, 2, 9]
    check s.`set`(series("m", @[false, true, false]), 0).toList(int) == @[1, 0, 3]

  test "dtypeOf":
    let df = newDataFrame(series("a", @[1.5, 2.5]), series("b", @[1'i32, 2'i32]))
    let r = df.select(col("a").cast(dtypeOf("b"), strict = false), dtypeOf("b").display.alias("t"))
    check r.dtype("a") == Int32
    check r.toList("t", string)[0] == "i32"
