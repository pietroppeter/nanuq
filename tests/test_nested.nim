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
