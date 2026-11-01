import std/[unittest, options, streams, os, strutils]
import nanuq

suite "json":
  test "read json":
    let json = """[{"bear": "Ada", "cubs": ["Bo"], "den": {"lat": 78.2}},
                   {"bear": "Cy", "cubs": [], "den": {"lat": 79.0}}]"""
    let df = readJson(newStringStream(json))
    check df.columns == @["bear", "cubs", "den"]
    check df.dtype("cubs") == List(String)
    check df.dtype("den") == Struct({"lat": Float64})
    check df.toList("cubs", seq[string]) == @[@["Bo"], @[]]

  test "read ndjson with overrides and schema":
    let r = readNdjson(newStringStream("{\"a\": 1}\n{\"a\": 2}\n"), schemaOverrides = {"a": Float64})
    check r.dtype("a") == Float64
    let s = readNdjson(newStringStream("{\"a\": 1, \"b\": \"x\"}\n"), schema = {"a": Int32, "b": String})
    check s.dtype("a") == Int32
    expect PolarsError:
      discard readJson(newStringStream("not json"))

  test "scan ndjson":
    let path = getTempDir() / "nanuq_bears.ndjson"
    writeFile(path, "{\"bear\": \"Ada\", \"kg\": 410}\n{\"bear\": \"Bo\", \"kg\": 380}\n{\"bear\": \"Cy\", \"kg\": 500}\n")
    let r = scanNdjson(path, rowIndexName = "i").filter(col("kg") > 400).collect
    check r.toList("bear", string) == @["Ada", "Cy"]
    check r.toList("i", int) == @[0, 2]
    check scanNdjson(path, nRows = 2).collect.height == 2

  test "write and round trip":
    let df = newDataFrame:
      bear: ["Ada", "Bo"]
      cubs: [@["Cy"], @[]]
      den: [(lat: 78.2, lon: 1.0), (lat: 79.0, lon: 2.0)]
    check df.toJson.startsWith("[{\"bear\":\"Ada\"")
    check df.toNdjson.count('\n') == 2
    let path = getTempDir() / "nanuq_rt.ndjson"
    df.writeNdjson(path)
    let back = readNdjson(path)
    check $back == $df
    let jpath = getTempDir() / "nanuq_rt.json"
    df.writeJson(jpath)
    check $readJson(jpath) == $df
    var ss = newStringStream()
    df.writeJson(ss)
    check ss.data == df.toJson
