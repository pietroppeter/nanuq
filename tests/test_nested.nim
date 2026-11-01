import std/[unittest, options, strutils]
import nanuq

type
  Point = object
    x: int
    y: float
  Den = object
    name: string
    cubs: seq[string]
    loc: Point
    note: Option[string]

suite "nested data types":
  test "constructors, names, equality":
    check $List(Int64) == "list[i64]"
    check $Array(Float64, 3) == "array[f64, 3]"
    check $Array(Int64, [2, 3]) == "array[i64, (2, 3)]"
    check Array(Int64, [2, 3]) == Array(Array(Int64, 3), 2)
    check Array(Int64, [2, 3]).shape == @[2, 3]
    let p = Struct({"x": Float64, "y": Float64})
    check $p == "struct[2]"
    check p.fields[1].name == "y"
    check List(p).inner == p
    check List(Int64) != List(Int32)
    check dataType(seq[seq[int]]) == List(List(Int64))
    check dataType(array[3, float]) == Array(Float64, 3)
    check dataType(Point) == Struct({"x": Int64, "y": Float64})

  test "list columns":
    let s = series("a", @[@[1, 2], @[], @[3]])
    check s.dtype == List(Int64)
    check s.toList(seq[int]) == @[@[1, 2], @[], @[3]]
    let e = series("e", newSeq[seq[int]](2))
    check e.dtype == List(Int64)
    check e.toList(seq[int]) == @[newSeq[int](), @[]]

  test "nulls in and of lists":
    let s = series("a", @[@[some(1), none(int)]])
    check s.toList(seq[Option[int]]) == @[@[some(1), none(int)]]
    expect InvalidOperationError:
      discard s.toList(seq[int])
    let r = series("r", [some(@[1]), none(seq[int])])
    check r.nullCount == 1
    check r.toList(Option[seq[int]]) == @[some(@[1]), none(seq[int])]
    expect InvalidOperationError:
      discard r.toList(seq[int])

  test "nested lists and strings":
    let s = series("a", @[@[@["a", "b"]], @[]])
    check s.dtype == List(List(String))
    check s.toList(seq[seq[string]]) == @[@[@["a", "b"]], @[]]

  test "arrays":
    let s = series("rgb", [[255, 0, 0], [0, 255, 0]])
    check s.dtype == Array(Int64, 3)
    check s.toList(array[3, int]) == @[[255, 0, 0], [0, 255, 0]]
    check s.toList(seq[int]) == @[@[255, 0, 0], @[0, 255, 0]]

  test "structs":
    let s = series("p", [Point(x: 1, y: 2.0), Point(x: 3, y: 4.0)])
    check s.dtype == dataType(Point)
    check s.toList(Point) == @[Point(x: 1, y: 2.0), Point(x: 3, y: 4.0)]
    check s.toList(tuple[y: float]) == @[(y: 2.0), (y: 4.0)]
    expect ColumnNotFoundError:
      discard s.toList(tuple[z: int])
    let o = series("o", [some((a: 1, b: "x")), none(tuple[a: int, b: string])])
    check o.nullCount == 1
    check o.toList(Option[tuple[a: int, b: string]]) == @[some((a: 1, b: "x")), none(tuple[a: int, b: string])]

  test "block, rows and round trip":
    let df = newDataFrame:
      tags: [@["polar", "bear"], @[], nil]
      point: [(x: 1, y: 2.0), (x: 3, y: 4.0), (x: 5, y: 6.0)]
      rgb: [[255, 0, 0], [0, 255, 0], [0, 0, 255]]
    check df.dtype("tags") == List(String)
    check df.dtype("point") == Struct({"x": Int64, "y": Float64})
    check df.dtype("rgb") == Array(Int64, 3)
    check df["point", 1, tuple[x: int]] == (x: 3)
    check df["tags", 2, Option[seq[string]]].isNone
    let dens = @[Den(name: "A", cubs: @["c1", "c2"], loc: Point(x: 1, y: 2.0), note: some("big")),
                 Den(name: "B", cubs: @[], loc: Point(x: 3, y: 4.0), note: none(string))]
    let f = dens.toDataFrame
    check f.rows(Den) == dens
    check $f.dtype("cubs") == "list[str]"

  test "list literal and casting":
    let df = newDataFrame(series("a", @[@[1, 2], @[3]]))
    let r = df.select(lit(@[1, 2]).alias("lit"))
    check r.dtype("lit") == List(Int64)
    check r.toList("lit", seq[int]) == @[@[1, 2]]
    let c = df.select(col("a").cast(List(Float64)), col("a").cast(seq[string]).alias("s"))
    check c.dtype("a") == List(Float64)
    check c.toList("s", seq[string]) == @[@["1", "2"], @["3"]]
    let two = newDataFrame(series("a", @[@[1, 2], @[3, 4]]))
    check two.select(col("a").cast(Array(Int64, 2))).dtype("a") == Array(Int64, 2)

  test "printing":
    let df = newDataFrame:
      tags: [@["polar", "bear"], @[]]
    check "list[str]" in $df
    check "[\"polar\", \"bear\"]" in $df

suite "book port needs (0.5)":
  let st = newDataFrame:
    p: [(x: 1, y: 2.0), (x: 3, y: 4.0)]
    l: [@[1, 2], @[3]]
    w: ["ab", "c"]

  test "sized numbers":
    let s = series("a", [1'i32, 2, 3])
    check s.dtype == Int32
    check s.toList(int32) == @[1'i32, 2, 3]
    let f = series("f", [some(1.5'f32), none(float32)])
    check f.dtype == Float32
    check f.toList(Option[float32]) == @[some(1.5'f32), none(float32)]
    let df = newDataFrame:
      a: [[1'i32, 2], [3'i32, 4]]
      b: [1'u8, 2]
    check df.dtype("a") == Array(Int32, 2)
    check df.dtype("b") == UInt8
    check df.toList("a", array[2, int32]) == @[[1'i32, 2], [3'i32, 4]]

  test "Series namespaces":
    let x = st["p"].struct.field("x")
    check x.name == "x"
    check x.toList(int) == @[1, 3]
    check st["p"].struct.renameFields(["u", "v"]).dtype.fields[0].name == "u"
    check st["l"].list.len.toList(int) == @[2, 1]
    check st["l"].list.get(0).toList(int) == @[1, 3]
    check st["w"].str.toUppercase.toList(string) == @["AB", "C"]

  test "Series as HTML":
    let h = st["w"].toHtml
    check "<small>shape: (2,)</small>" in h
    check "<th>w</th>" in h

  test "entropy and len()":
    let e = st.select(col("l").list.agg(element().entropy).alias("e"))
    check abs(e.toList("e", float)[0] - 0.6365141682948128) < 1e-12
    check e.toList("e", float)[1] == 0.0
    check st.select(len()).toList("len", int) == @[2]
    check st.groupBy("w").agg(len()).sort("w").toList("len", int) == @[1, 1]

  test "asStruct by name":
    check st.select(asStruct("w", "l")).dtype("w") == Struct({"w": String, "l": List(Int64)})

  test "frame interpolate and cast by type":
    let ip = newDataFrame:
      a: [1.0, NaN, 3.0]
      b: [some(1), none(int), some(5)]
    check ip.interpolate.toList("b", float) == @[1.0, 3.0, 5.0]
    let c = ip.cast({Float64: Float32})
    check c.dtype("a") == Float32
    check c.dtype("b") == Int64
    check ip.cast({col(SomeNumber): Float32}).dtype("b") == Float32

  test "explode several columns by name":
    let ex = newDataFrame:
      a: [@[1, 2], @[3, 4]]
      b: [@["x", "y"], @["z", "w"]]
    let r = ex.explode("a", "b")
    check r.toList("b", string) == @["x", "y", "z", "w"]
    check ex.lazy.explode("a", "b").collect.height == 4
