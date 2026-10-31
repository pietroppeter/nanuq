import std/[os, unittest, strutils, options]
import nanuq

let dir = getTempDir() / "nanuq_test_csv"
createDir(dir)

proc put(name, content: string): string =
  result = dir / name
  writeFile(result, content)

suite "scanCsv":
  test "is lazy and reads a glob":
    createDir(dir / "logs")
    writeFile(dir / "logs" / "a.csv", "x,y\n1,a\n2,b\n")
    writeFile(dir / "logs" / "b.csv", "x,y\n3,c\n4,d\n5,e\n")
    let lf = scanCsv(dir / "logs" / "*.csv")
    check lf.collect.shape == (5, 2)
    check lf.select(col("x").sum).collect["x", 0, int] == 15

  test "a glob over files with different columns fails when the query runs":
    createDir(dir / "mixed")
    writeFile(dir / "mixed" / "a.csv", "x,y\n1,a\n")
    writeFile(dir / "mixed" / "b.csv", "x,y,z\n2,b,true\n")
    expect NanuqError:
      discard scanCsv(dir / "mixed" / "*.csv").collect

suite "readCsv options":
  test "separator and null values":
    let p = put("semi.csv", "site;bears\nnorth;3\nsouth;lots\n")
    let df = readCsv(p, separator = ';', nullValues = ["lots"])
    check df.columns == @["site", "bears"]
    check df.dtype("bears") == Int64
    check df.toList("bears", Option[int]) == @[some(3), none(int)]

  test "schemaOverrides":
    let p = put("ints.csv", "n,s\n1,a\n2,b\n")
    let df = readCsv(p, schemaOverrides = {"n": Float64})
    check df.dtype("n") == Float64
    check df.dtype("s") == String

  test "schemaOverrides with a dtype Nanuq does not model raises":
    let p = put("ints2.csv", "n\n1\n")
    expect NanuqError:
      discard readCsv(p, schemaOverrides = {"n": DataType(kind: DataTypeKind.Other, name: "date")})

  test "skipRows and nRows":
    var content = "# census export\n# do not edit\nid,v\n"
    for i in 1..10: content.add $i & "," & $(i * 10) & "\n"
    let p = put("preamble.csv", content)
    let df = readCsv(p, skipRows = 2, nRows = 3)
    check df.columns == @["id", "v"]
    check df.toList("id", int) == @[1, 2, 3]
    check readCsv(p, skipRows = 2, nRows = none(int)).height == 10
    check readCsv(p, skipRows = 2, nRows = some(4)).height == 4

  test "columns":
    let p = put("abc.csv", "a,b,c\n1,2,3\n")
    let df = readCsv(p, columns = ["c", "a"])
    check df.columns == @["c", "a"]
    check scanCsv(p, columns = ["b"]).collect.columns == @["b"]

  test "hasHeader = false":
    let p = put("noheader.csv", "1,x\n2,y\n")
    let df = readCsv(p, hasHeader = false)
    check df.shape == (2, 2)
    check df.columns == @["column_1", "column_2"]

  test "inferSchemaLength and ignoreErrors":
    var content = "v\n"
    for i in 1..5: content.add $i & "\n"
    content.add "2.5\n"
    let p = put("late_float.csv", content)
    expect NanuqError:
      discard readCsv(p, inferSchemaLength = 2)
    check readCsv(p, inferSchemaLength = none(int)).dtype("v") == Float64
    let lenient = readCsv(p, inferSchemaLength = 2, ignoreErrors = true)
    check lenient.height == 6
    check lenient.nullCount("v") == 1

  test "decimalComma":
    let p = put("comma.csv", "v;w\n1,5;x\n2,25;y\n")
    let df = readCsv(p, separator = ';', decimalComma = true)
    check df.dtype("v") == Float64
    check df.toList("v", float) == @[1.5, 2.25]

suite "writeCsv options":
  test "separator and decimal comma round trip":
    let p = dir / "out_comma.csv"
    newDataFrame(series("v", [1.5, 2.0]), series("s", ["a", "b"])).writeCsv(
      p, separator = ';', decimalComma = true)
    check "1,5" in readFile(p)
    let back = readCsv(p, separator = ';', decimalComma = true)
    check back.toList("v", float) == @[1.5, 2.0]

  test "quoteStyle":
    let df = newDataFrame(series("n", [1]), series("s", ["a"]))
    let p = dir / "out_quote.csv"
    df.writeCsv(p, quoteStyle = QuoteStyle.Always)
    check readFile(p) == "\"n\",\"s\"\n\"1\",\"a\"\n"
    df.writeCsv(p, quoteStyle = NonNumeric)
    check readFile(p) == "\"n\",\"s\"\n1,\"a\"\n"

  test "nullValue, floatPrecision and includeHeader":
    let df = newDataFrame(series("x", [some(3.14159), none(float)]))
    let p = dir / "out_na.csv"
    df.writeCsv(p, nullValue = "NA", floatPrecision = 2)
    check readFile(p) == "x\n3.14\nNA\n"
    df.writeCsv(p, includeHeader = false, floatPrecision = some(1))
    check readFile(p) == "3.1\n\n"

removeDir(dir)
