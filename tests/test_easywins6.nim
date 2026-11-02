import std/[unittest, options, math, tables, os, streams, strutils, sequtils, times]
import nanuq

suite "coverage easy wins (0.6): pure Nim":
  let df = newDataFrame(series("station", @["A", "B", "A"]), series("rain", @[1.5, NaN, 3.0]),
                        series("n", @[1, 2, 3]))

  test "empty frames":
    let e = newDataFrame(schema = {"kg": Int64, "bear": String, "day": dataType(Date)})
    check e.height == 0
    check e.isEmpty
    check e.columns == @["kg", "bear", "day"]
    check e.dtype("day") == dataType(Date)
    let e2 = newDataFrame(schema = df.schema)
    check e2.schema == df.schema
    check df.clear.height == 0
    check df.clear.schema == df.schema
    let c = df.clear(2)
    check c.height == 2
    check c.toList("n", Option[int]) == @[none(int), none(int)]
    check df.lazy.clear(1).collect.height == 1
    check not df.isEmpty
    check series("x", newSeq[int]()).isEmpty

  test "getColumnIndex":
    check df.getColumnIndex("rain") == 1
    expect ColumnNotFoundError:
      discard df.getColumnIndex("nope")

  test "rowsByKey":
    let t = df.rowsByKey("station", string, tuple[n: int])
    check t["A"].mapIt(it.n) == @[1, 3]
    check toSeq(t.keys) == @["A", "B"]
    let u = df.rowsByKey("station", string, tuple[n: int], unique = true)
    check u["A"].n == 3

  test "frame shift, dropNans, first, last":
    check df.shift(1).toList("n", Option[int]) == @[none(int), some(1), some(2)]
    check df.shift(-1, fillValue = 0).toList("n", int) == @[2, 3, 0]
    check df.dropNans.toList("n", int) == @[1, 3]
    check df.dropNans("n").height == 3
    check df.lazy.first.collect.toList("n", int) == @[1]
    check df.lazy.last.collect.toList("n", int) == @[3]
    check df.lazy.shift(2).collect.toList("n", Option[int]) == @[none(int), none(int), some(1)]

  test "dt.epoch":
    let d = newDataFrame(series("d", @[date(1970, 1, 3)]))
    check d.select(col.d.dt.epoch(EpochUnit.Days)).toList("d", int) == @[2]
    check d.select(col.d.dt.epoch(EpochUnit.Seconds)).toList("d", int) == @[2 * 86400]
    check d.select(col.d.dt.epoch).toList("d", int) == @[2 * 86400 * 1_000_000]

  test "table formatting":
    let small = newDataFrame(series("a", @[1]))
    withConfig(asciiTables = true):
      check "+-----+" in $small
    check "┌" in $small
    withConfig(tblHideColumnDataTypes = true, tblHideDataframeShape = true):
      check "i64" notin $small
      check "shape" notin $small
    withConfig(tblFormatting = TableFormat.Markdown):
      check "| a   |" in $small
    setTblColumnDataTypeInline()
    check "a (i64)" in $small
    resetConfig()
    check "a (i64)" notin $small

  test "bin on a Series":
    let s = newDataFrame(series("b", @["ab", "cd"])).select(col.b.cast(Binary)).getColumn("b")
    check s.bin.size.toList(int) == @[2, 2]

suite "coverage easy wins (0.6): small bridge calls":
  test "eqMissing and neMissing":
    let f = newDataFrame(series("a", [some(1), none(int)]), series("b", [some(1), none(int)]))
    check f.select(col.a.eqMissing(col.b)).toList("a", bool) == @[true, true]
    check f.select(col.a.neMissing(1)).toList("a", bool) == @[false, true]

  test "nth":
    let f = newDataFrame(series("a", @[1]), series("b", @[2]), series("c", @[3]))
    check f.select(nth(0, -1)).columns == @["a", "c"]

  test "cumulativeEval and roundSigFigs":
    let f = newDataFrame(series("x", @[1, 2, 3]))
    check f.select(col.x.cumulativeEval(element().sum)).toList("x", int) == @[1, 3, 6]
    let g = newDataFrame(series("x", @[1234.5, 0.012345]))
    check g.select(col.x.roundSigFigs(2)).toList("x", float) == @[1200.0, 0.012]

  test "century, millennium, time zone offsets":
    let f = newDataFrame(series("d", @[date(2000, 6, 1), date(2001, 1, 1)]))
    check f.select(col.d.dt.century).toList("d", int) == @[20, 21]
    check f.select(col.d.dt.millennium).toList("d", int) == @[2, 3]
    let z = newDataFrame(series("t", @[dateTime(2026, mJul, 1, 12, zone = utc())]))
      .select(col.t.dt.replaceTimeZone("Europe/Rome"))
    check z.select(col.t.dt.dstOffset.dt.totalHours).toList("t", int) == @[1]
    check z.select(col.t.dt.baseUtcOffset.dt.totalHours).toList("t", int) == @[1]

  test "timeRange, escapeRegex, concatArr":
    let t = select(timeRange(timeOfDay(9), timeOfDay(12), "1h").alias("t"))
    check t.height == 4
    let r = select(timeRanges(timeOfDay(9), timeOfDay(10), "30m").alias("t"))
    check r.select(col.t.list.len).toList("t", int) == @[3]
    let s = newDataFrame(series("s", @["a.b*c"]))
    check s.select(col.s.str.escapeRegex).toList("s", string) == @["a\\.b\\*c"]
    let a = newDataFrame(series("x", @[1, 2]), series("y", @[3, 4]))
    check a.select(concatArr(col.x, col.y).alias("xy")).dtype("xy").kind == DataTypeKind.Array

  test "CSV commentPrefix and Parquet hivePartitioning":
    check readCsv(newStringStream("# note\na,b\n1,2\n"), commentPrefix = "#").columns == @["a", "b"]
    let dir = getTempDir() / "nanuq_hive6"
    removeDir(dir)
    newDataFrame(series("year", @[2024, 2025]), series("n", @[1, 2])).lazy.sinkParquet(
      PartitionBy(basePath: dir, key: @["year"], includeKey: false), mkdir = true)
    check "year" in scanParquet(dir / "**/*.parquet", hivePartitioning = true).collect.columns
    check "year" notin scanParquet(dir / "**/*.parquet", hivePartitioning = false).collect.columns

  test "cache and optimization flags":
    let lf = newDataFrame(series("x", @[1, 2, 3])).lazy.filter(col.x > 1)
    check lf.cache.collect.height == 2
    check lf.collect(QueryOptFlags.none).height == 2
    check lf.collect(QueryOptFlags(predicatePushdown: false)).height == 2
    check "FILTER" in lf.withOptimizations(QueryOptFlags.none).explain

  test "rechunk, shrinkToFit, nChunks":
    let path = getTempDir() / "nanuq_chunks.parquet"
    newDataFrame(series("x", @[1, 2, 3])).writeParquet(path, rowGroupSize = 1)
    let v = readParquet(path)
    check v.nChunks == 3
    check v.rechunk.nChunks == 1
    check v.shrinkToFit.height == 3

  test "matchToSchema":
    let f = newDataFrame(series("b", @[1'i32]), series("a", @["x"]))
    let m = f.matchToSchema({"a": String, "b": Int64, "c": Float64},
                            missingColumns = MissingColumns.Insert,
                            integerCast = CastPolicy.Upcast)
    check m.columns == @["a", "b", "c"]
    check m.dtype("b") == Int64
    expect PolarsError:
      discard f.matchToSchema({"a": String})

  test "readOds":
    let ods = currentSourcePath.parentDir / "data" / "bears.ods"
    let d = readOds(ods)
    check d.columns == @["bear", "kg"]
    check d.toList("kg", float) == @[410.0, 380.0]

suite "coverage easy wins (0.6): one more Polars feature":
  test "isClose":
    let f = newDataFrame(series("x", @[1.0, 1.1]))
    check f.select(col.x.isClose(1.0, absTol = 0.05)).toList("x", bool) == @[true, false]

  test "mergeSorted":
    let a = newDataFrame(series("k", @[1, 4]))
    let b = newDataFrame(series("k", @[2, 3, 5]))
    check a.mergeSorted(b, "k").toList("k", int) == @[1, 2, 3, 4, 5]

  test "business days":
    let f = newDataFrame(series("d", @[date(2026, 10, 30)]))  # a Friday
    check f.select(col.d.dt.addBusinessDays(1)).toList("d", Date) == @[date(2026, 11, 2)]
    check f.select(col.d.dt.addBusinessDays(1, holidays = [date(2026, 11, 2)])).toList("d", Date) ==
      @[date(2026, 11, 3)]
    check f.select(col.d.dt.isBusinessDay).toList("d", bool) == @[true]
    check f.select(col.d.dt.isBusinessDay(weekMask = [true, true, true, true, false, false, false])).toList("d", bool) == @[false]
    check select(businessDayCount(date(2026, 11, 2), date(2026, 11, 9)).alias("n")).toList("n", int) == @[5]
    let sat = newDataFrame(series("d", @[date(2026, 10, 31)]))
    check sat.select(col.d.dt.addBusinessDays(0, roll = Roll.Forward)).toList("d", Date) == @[date(2026, 11, 2)]

  test "str.normalize and reinterpret":
    let s = newDataFrame(series("s", @["é"]))
    check s.select(col.s.str.normalize).toList("s", string) == @["é"]
    check s.select(col.s.str.normalize(UnicodeForm.NFD)).toList("s", string) == @["é"]
    let n = newDataFrame(series("x", @[-1]))
    check n.select(col.x.reinterpret(signed = false)).dtype("x") == UInt64

  test "IPC streams":
    let path = getTempDir() / "nanuq_stream.arrows"
    let f = newDataFrame(series("x", @[1, 2]))
    f.writeIpcStream(path)
    check readIpcStream(path).toList("x", int) == @[1, 2]
    check readIpcStream(newStringStream(readFile(path))).height == 2
    f.writeIpcStream(path, compression = IpcCompression.Zstd)
    check readIpcStream(path).height == 2
