import std/[unittest, options, os, streams]
import nanuq

let dir = getTempDir() / "nanuq_io"
createDir dir

proc riders(): DataFrame =
  newDataFrame:
    rider: ["Seixas", "Pogačar", "Evenepoel"]
    wins: [3, 22, nil]
    born: [date(2006, 9, 24), date(1998, 9, 21), date(2000, 1, 25)]
    pct: [0.12, 0.31, 0.2]

suite "parquet":
  test "round trip keeps dtypes and nulls":
    let path = dir / "riders.parquet"
    riders().writeParquet(path)
    let back = readParquet(path)
    check $back == $riders()
    check back.schema == riders().schema

  test "options when reading":
    let path = dir / "riders.parquet"
    riders().writeParquet(path)
    let r = readParquet(path, nRows = 2, columns = ["wins", "rider"], rowIndexName = "nr",
                        rowIndexOffset = 1)
    check r.columns == @["nr", "wins", "rider"]
    check r.toList("nr", int) == @[1, 2]
    check r.height == 2
    let i = readParquet(path, rowIndexName = "nr", rowIndexOffset = 1)
    check i.columns[0] == "nr"
    check i.toList("nr", int) == @[1, 2, 3]

  test "lazy scan with a glob":
    riders().writeParquet(dir / "part_1.parquet")
    riders().writeParquet(dir / "part_2.parquet")
    let n = scanParquet(dir / "part_*.parquet").filter(col.wins.isNotNull).collect.height
    check n == 4

  test "compressions":
    for c in ParquetCompression:
      let path = dir / ("c_" & $c & ".parquet")
      riders().writeParquet(path, compression = c)
      check readParquet(path).height == 3
    riders().writeParquet(dir / "z.parquet", compressionLevel = 19)
    riders().writeParquet(dir / "g.parquet", compression = ParquetCompression.Gzip,
                          compressionLevel = some(9), statistics = false, rowGroupSize = 1)
    check readParquet(dir / "g.parquet").height == 3
    expect ValueError:
      riders().writeParquet(dir / "s.parquet", compression = ParquetCompression.Snappy,
                            compressionLevel = 3)
    expect PolarsError:
      riders().writeParquet(dir / "z.parquet", compressionLevel = 99)

  test "from a stream":
    let path = dir / "riders.parquet"
    riders().writeParquet(path)
    let back = readParquet(newStringStream(readFile(path)), columns = ["rider"])
    check back.toList("rider", string) == @["Seixas", "Pogačar", "Evenepoel"]

  test "errors":
    expect PolarsError:
      discard readParquet(newStringStream("not parquet"))
    expect IOError:
      riders().writeParquet("no/such/dir/x.parquet")

suite "ipc":
  test "round trip and compressions":
    for c in IpcCompression:
      let path = dir / ("riders_" & $c & ".arrow")
      riders().writeIpc(path, compression = c)
      check $readIpc(path) == $riders()
    let path = dir / "riders_Uncompressed.arrow"
    check scanIpc(path, nRows = 1).collect.height == 1
    check readIpc(path, columns = ["born"]).toList("born", Date)[0] == date(2006, 9, 24)
    check readIpc(path, rowIndexName = "i").toList("i", int) == @[0, 1, 2]
    check readIpc(newFileStream(path)).height == 3

suite "csv from a stream":
  test "same options as files":
    let s = newStringStream("# note\nstation;bears\nNorth;3\nSouth;NA\n")
    let df = readCsv(s, separator = ';', skipRows = 1, nullValues = ["NA"])
    check df.toList("bears", Option[int]) == @[some(3), none(int)]
    let d = readCsv(newStringStream("day\n2026-07-04\n"), tryParseDates = true)
    check d.dtype("day") == Date
    expect NoDataError:
      discard readCsv(newStringStream(""))
