import std/[unittest, options, strutils]
import nanuq

type Bear = object
  name: string
  kg: int

suite "nim callbacks":
  let df = newDataFrame:
    bear: ["Ada", "Bo", "Cy"]
    kg: [410, 380, 500]
    cubs: [1, 0, 2]

  test "mapElements typed":
    let r = df.select(col("kg").mapElements(proc (x: int): string = "kg " & $x).alias("s"),
                      col("bear").mapElements(proc (x: string): int = x.len).alias("n"))
    check r.dtype("s") == String
    check r.toList("s", string) == @["kg 410", "kg 380", "kg 500"]
    check r.toList("n", int) == @[3, 2, 2]

  test "mapElements with nulls and closures":
    let d = newDataFrame:
      a: [1, nil, 3]
    let k = 10
    let r = d.select(col("a").mapElements(proc (x: int): int = x * k))
    check r.toList("a", Option[int]) == @[some(10), none(int), some(30)]
    let o = d.select(col("a").mapElements(proc (x: Option[int]): bool = x.isNone))
    check o.toList("a", bool) == @[false, true, false]

  test "mapElements on structs and lists":
    let r = df.select(asStruct(col("bear").alias("name"), col("kg")).mapElements(
                        proc (b: Bear): string = b.name & ":" & $b.kg).alias("s"))
    check r.toList("s", string) == @["Ada:410", "Bo:380", "Cy:500"]
    let l = newDataFrame:
      xs: [@[1, 2], @[3]]
    check l.select(col("xs").mapElements(proc (x: seq[int]): int = x.len)).toList("xs", int) == @[2, 1]

  test "mapBatches":
    let r = df.select(col("kg").mapBatches(proc (s: Series): Series = s * 2))
    check r.toList("kg", int) == @[820, 760, 1000]
    let f = df.select(col("kg").mapBatches(proc (s: Series): Series = s / 10, Float64))
    check f.dtype("kg") == Float64
    let g = df.groupBy("cubs").agg(col("kg").mapBatches(proc (s: Series): Series = s.max).alias("m"))
    check g.height == 3

  test "errors":
    expect ComputeError:
      discard df.select(col("kg").mapElements(proc (x: int): int =
        raise newException(ValueError, "no bears")))
    try:
      discard df.select(col("kg").mapElements(proc (x: int): int =
        raise newException(ValueError, "no bears")))
    except ComputeError as e:
      check "no bears" in e.msg

  test "fold, reduce, cumFold":
    let r = df.select(fold(lit(0), proc (acc, x: Series): Series = acc + x, col("kg"), col("cubs")).alias("f"),
                      reduce(proc (acc, x: Series): Series = acc + x, col("kg"), col("cubs")).alias("r"))
    check r.toList("f", int) == @[411, 380, 502]
    check r.toList("r", int) == @[411, 380, 502]
    let c = df.select(cumFold(lit(0), proc (acc, x: Series): Series = acc + x, [col("kg"), col("cubs")]).alias("c"))
    check c.dtype("c").kind == DataTypeKind.Struct

  test "name.map":
    let r = df.select(col("*").name.map(proc (n: string): string = n.toUpperAscii))
    check r.columns == @["BEAR", "KG", "CUBS"]

  test "mapGroups":
    let d = newDataFrame:
      den: ["A", "B", "A"]
      kg: [1, 2, 3]
    let r = d.groupBy("den").mapGroups(proc (g: DataFrame): DataFrame = g.head(1))
    check r.toList("den", string) == @["A", "B"]
    check r.toList("kg", int) == @[1, 2]
