import std/[unittest, os, sequtils]
import nanuq

suite "streaming":
  let dir = getTempDir() / "nanuq_test_sinks"
  removeDir(dir)

  test "collect with an engine":
    let lf = newDataFrame(series("g", @["a", "b", "a", "c"]), series("x", @[1, 2, 3, 4])).lazy
    let q = lf.groupBy("g").agg(col("x").sum)
    let a = q.collect(engine = Engine.InMemory).sort("g")
    let b = q.collect(engine = Engine.Streaming).sort("g")
    check a.equals(b)
    check q.collect(Engine.Auto).height == 3
    let all = collectAll([q, lf], Engine.Streaming)
    check all[1].height == 4

  test "sinks":
    let lf = newDataFrame(series("bear", @["Ada", "Bo"]), series("kg", @[410, 380])).lazy
    lf.sinkCsv(dir / "bears.csv", mkdir = true)
    check readFile(dir / "bears.csv") == "bear,kg\nAda,410\nBo,380\n"
    lf.sinkParquet(dir / "bears.parquet")
    check readParquet(dir / "bears.parquet").toList("kg", int) == @[410, 380]
    lf.sinkIpc(dir / "bears.arrow")
    check readIpc(dir / "bears.arrow").height == 2
    lf.sinkNdjson(dir / "bears.ndjson")
    check readNdjson(dir / "bears.ndjson").toList("bear", string) == @["Ada", "Bo"]
    lf.sinkCsv(dir / "semi.csv", separator = ';', includeHeader = false)
    check readFile(dir / "semi.csv") == "Ada;410\nBo;380\n"

  test "lazy sinks":
    let lf = newDataFrame(series("kg", @[410, 380])).lazy
    let s = lf.sinkParquet(dir / "lazy.parquet", lazy = true)
    check s is LazyFrame
    check not fileExists(dir / "lazy.parquet")
    discard collectAll([s, lf.sinkNdjson(dir / "lazy.ndjson", lazy = true)])
    check fileExists(dir / "lazy.parquet")
    check readNdjson(dir / "lazy.ndjson").height == 2

  test "missing directory":
    let lf = newDataFrame(series("kg", @[1])).lazy
    expect IOError:
      lf.sinkCsv(dir / "nope" / "x.csv")
    check not fileExists(dir / "nope" / "x.csv")
    expect ValueError:
      lf.sinkParquet(dir / "x.parquet", compression = ParquetCompression.Snappy, compressionLevel = 3)

  test "partitioned sinks":
    let base = dir / "by_year"
    let df = newDataFrame(series("year", @[2024, 2024, 2025]), series("n", @[1, 2, 3]))
    df.lazy.sinkParquet(PartitionBy(basePath: base, key: @["year"]), mkdir = true)
    check dirExists(base / "year=2024")
    let back = scanParquet(base / "**/*.parquet").sort("n").collect
    check back.toList("n", int) == @[1, 2, 3]
    let rows = dir / "by_rows"
    newDataFrame(series("i", toSeq(0..9))).lazy.sinkCsv(
      PartitionBy(basePath: rows, maxRowsPerFile: 4), mkdir = true)
    var total = 0
    var files = 0
    for f in walkDirRec(rows):
      total += readCsv(f).height
      inc files
    check total == 10
    check files >= 3

  test "profile":
    let (res, timings) = newDataFrame(series("x", @[1, 2, 3])).lazy.select(col("x").sum).profile
    check res.toList("x", int) == @[6]
    check timings.columns == @["node", "start", "end"]
    check timings.height >= 1
