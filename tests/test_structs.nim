import std/[unittest, options]
import nanuq

suite "structs":
  test "asStruct and fields":
    let df = newDataFrame:
      bear: ["Ada", "Bo"]
      kg: [410, 380]
    let s = df.select(asStruct(col("bear"), col("kg") * 2).alias("s"))
    check s.dtype("s") == Struct({"bear": String, "kg": Int64})
    check s.toList("s", tuple[bear: string, kg: int]) == @[(bear: "Ada", kg: 820), (bear: "Bo", kg: 760)]
    let f = s.select(col("s").struct.field("kg"), col("s").struct["bear"].alias("b"),
                     col("s").struct.field(0).alias("first"))
    check f.toList("kg", int) == @[820, 760]
    check f.toList("b", string) == @["Ada", "Bo"]
    check f.toList("first", string) == @["Ada", "Bo"]
    check s.select(col("s").struct.unnest).columns == @["bear", "kg"]
    expect PolarsError:
      discard s.select(col("s").struct.field("z"))

  test "rename, withFields, json":
    let df = newDataFrame:
      p: [(x: 1, y: 2.0), (x: 3, y: 4.0)]
    let r = df.select(col("p").struct.renameFields(["a", "b"]).struct.unnest)
    check r.columns == @["a", "b"]
    let w = df.select(col("p").struct.withFields((col("p").struct.field("x") * 10).alias("z")))
    check w.toList("p", tuple[x: int, z: int]) == @[(x: 1, z: 10), (x: 3, z: 30)]
    check df.select(col("p").struct.jsonEncode).toList("p", string) == @["""{"x":1,"y":2.0}""", """{"x":3,"y":4.0}"""]

  test "unnest frames":
    let df = newDataFrame:
      bear: ["Ada", "Bo"]
      den: [(lat: 78.2, lon: 15.6), (lat: 79.0, lon: 16.1)]
    check df.unnest("den").columns == @["bear", "lat", "lon"]
    check df.unnest("den", separator = "_").columns == @["bear", "den_lat", "den_lon"]
    check df.lazy.unnest("den").collect.width == 3

  test "valueCounts":
    let df = newDataFrame:
      island: ["Biscoe", "Dream", "Biscoe"]
    let r = df.select(col("island").valueCounts(sort = true)).unnest("island")
    check r.toList("island", string) == @["Biscoe", "Dream"]
    check r.toList("count", int) == @[2, 1]
    let p = df.select(col("island").valueCounts(sort = true, normalize = true)).unnest("island")
    check p.columns == @["island", "proportion"]

suite "arrays":
  test "arr namespace":
    let df = newDataFrame:
      rgb: [[255, 0, 0], [10, 20, 30]]
    let r = df.select(col("rgb").arr.sum.alias("sum"), col("rgb").arr.get(1).alias("g"),
                      col("rgb").arr.toList.alias("list"), col("rgb").arr.max.alias("max"),
                      col("rgb").arr.contains(30).alias("has30"))
    check r.toList("sum", int) == @[255, 60]
    check r.toList("g", int) == @[0, 20]
    check r.dtype("list") == List(Int64)
    check r.toList("has30", bool) == @[false, true]
    check df.select(col("rgb").arr.toStruct).dtype("rgb").fields.len == 3
    check df.select(col("rgb").arr.explode).height == 6
