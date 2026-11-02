import std/[unittest, math, options, times]
import nanuq

suite "arrow":
  test "series round trip":
    var ex = series("kg", @[410, 380]).toArrow
    check $ex.schema.format == "l"
    check ex.array.length == 2
    let back = fromArrow(ex, name = "mass")
    check ex.array.release == nil
    check back.name == "mass"
    check back.toList(int) == @[410, 380]
    var ex2 = series("s", [some("a"), none(string)]).toArrow
    check fromArrow(ex2).toList(Option[string]) == @[some("a"), none(string)]

  test "export released when unused":
    for i in 0 ..< 100:
      let ex = series("x", @[1.0, 2.0]).toArrow
      check ex.array.length == 2

  test "frames":
    let df = newDataFrame:
      bear: ["Ada", "Bo"]
      kg: [410.0, 380.5]
      cubs: [@["Cy"], @[]]
    let df2 = df.withColumns(asStruct(col("bear"), col("kg")).alias("s"),
                             lit(dateTime(2024, mJan, 1, zone = utc())).alias("t"))
    var stream = df2.toArrow
    let back = fromArrow(stream)
    check back.equals(df2)
    check stream.release == nil

  test "views":
    let df = newDataFrame(series("kg", @[410.0, 380.5, 455.0]), series("n", @[1, 2, 3]))
    let v = df.view("kg", float)
    check v.len == 3
    check v[1] == 380.5
    check sum(v.toOpenArray) == 1245.5
    var t = 0
    for x in df.view("n", int): t += x
    check t == 6
    let sl = df.slice(1, 2).getColumn("n").view(int)
    check sl[0] == 2
    expect InvalidOperationError:
      discard df.view("n", float)
    expect InvalidOperationError:
      discard series("o", [some(1), none(int)]).view(int)

  test "mapElements fast path":
    let df = newDataFrame(series("x", @[1, 2, 3]))
    let r = df.select(col("x").mapElements(proc (x: int): float = x.float * 1.5))
    check r.toList("x", float) == @[1.5, 3.0, 4.5]
