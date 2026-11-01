import std/[unittest, os, strutils]
import nanuq

suite "serialization":
  test "lazy frames":
    let lf = newDataFrame(series("kg", @[410, 380, 455])).lazy.filter(col("kg") > 400)
    let bin = lf.serialize
    check deserialize(LazyFrame, bin).collect.toList("kg", int) == @[410, 455]
    let js = lf.serialize(SerializationFormat.Json)
    check js.startsWith("{")
    check deserialize(LazyFrame, js, SerializationFormat.Json).collect.height == 2
    let path = getTempDir() / "nanuq_plan.bin"
    lf.serialize(path)
    check deserializeFile(LazyFrame, path).collect.height == 2
    expect PolarsError:
      discard deserialize(LazyFrame, "garbage")

  test "callbacks can't be serialized":
    let lf = newDataFrame(series("x", @[1, 2])).lazy.select(
      col("x").mapElements(proc (x: int): int = x * 2))
    expect PolarsError:
      discard lf.serialize

  test "expressions":
    let e = (col("kg") * 2).alias("double")
    let back = deserialize(Expr, e.meta.serialize)
    check back.meta.eq(e)
    check newDataFrame(series("kg", @[1, 2])).select(back).toList("double", int) == @[2, 4]
    let j = deserialize(Expr, e.meta.serialize(SerializationFormat.Json), SerializationFormat.Json)
    check j.meta.eq(e)
    check not col("a").meta.eq(col("b"))
    check col("a").meta.ne(col("b"))

  test "meta":
    let e = (col("a") + col("b")).alias("c")
    check e.meta.pop.len == 1
    check (col("a") + col("b")).meta.pop.len == 2
    check col("^x.*$").meta.isRegexProjection
    check not col("a").meta.isRegexProjection
    check col("a").alias("b").meta.isColumnSelection(allowAliasing = true)
    check not col("a").alias("b").meta.isColumnSelection
    check lit(1).alias("x").meta.isLiteral(allowAliasing = true)
    check (col("a") + 1).meta.treeFormat.len > 0
