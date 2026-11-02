import std/[unittest, os, options, tables]
import nanuq

suite "excel":
  let dir = getTempDir() / "nanuq_excel"
  createDir(dir)

  test "round trip":
    let path = dir / "bears.xlsx"
    let df = newDataFrame(series("bear", @["Ada", "Bo"]), series("kg", @[410, 380]),
                          series("w", @[1.5, 2.25]), series("ok", @[true, false]),
                          series("seen", @[date(2024, 3, 1), date(2024, 3, 9)]))
    df.writeExcel(path, worksheet = "census", autofit = true)
    let back = readExcel(path)
    check back.equals(df)
    check readExcel(path, sheetName = "census").height == 2

  test "options":
    let path = dir / "opts.xlsx"
    newDataFrame(series("a", @[1, 2, 3]), series("b", @["x", "y", "z"])).writeExcel(path)
    let r = readExcel(path, skipRows = 1, hasHeader = false)
    check r.columns == @["column_1", "column_2"]
    check r.height == 3
    check readExcel(path, columns = ["b"]).columns == @["b"]
    check readExcel(path, schemaOverrides = {"a": Float64}).dtype("a") == Float64
    let sheets = readExcelSheets(path)
    check sheets.len == 1
    check "Sheet1" in sheets

  test "nulls and datetimes":
    let path = dir / "nulls.xlsx"
    let df = newDataFrame(series("n", [some(1), none(int)]),
                          series("t", @[dateTime(2024, mJan, 1, 12, 30, 0, zone = utc()),
                                        dateTime(2024, mJan, 2, 0, 0, 1, zone = utc())]))
    df.writeExcel(path)
    let r = readExcel(path)
    check r.toList("n", Option[int]) == @[some(1), none(int)]
    check r.dtype("t").kind == DataTypeKind.Datetime

  test "errors":
    expect IOError:
      discard readExcel(dir / "bears.xlsx", sheetName = "nope")
    expect IOError:
      newDataFrame(series("a", @[1])).writeExcel(dir / "missing" / "x.xlsx")
    expect IOError:
      discard readExcel(dir / "nofile.xlsx")
