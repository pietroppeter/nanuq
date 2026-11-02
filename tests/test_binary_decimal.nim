import std/[unittest, options]
import nanuq

suite "binary and decimal":
  test "binary":
    let s = series("sig", ["\x00\xff", "bear"], Binary)
    check s.dtype == Binary
    check $Binary == "Binary"
    let df = newDataFrame(s)
    check df.toList("sig", string) == @["\x00\xff", "bear"]
    let c = newDataFrame(series("s", @["x", "y"])).cast(Binary)
    check c.dtype("s") == Binary
    check c.toList("s", string) == @["x", "y"]
    let o = newDataFrame(series("o", [some("a"), none(string)], Binary))
    check o.toList("o", Option[string]) == @[some("a"), none(string)]

  test "decimal":
    let df = newDataFrame(series("price", ["1.25", "10.50", "0.10"], Decimal(10, 2)))
    check df.dtype("price") == Decimal(10, 2)
    check $df.dtype("price") == "Decimal(10, 2)"
    check df.toList("price", string) == @["1.25", "10.50", "0.10"]
    check df.toList("price", float) == @[1.25, 10.5, 0.1]
    check df.select(col("price").sum).toList("price", string) == @["11.85"]
    expect ValueError:
      discard Decimal(40, 2)
    let t = newDataFrame(series("s", @["3.14"])).select(col("s").str.toDecimal(2))
    check t.dtype("s").kind == DataTypeKind.Decimal
    check t.dtype("s").scale == 2

  test "bin namespace":
    let df = newDataFrame(series("b", ["bear", "cub"], Binary))
    let r = df.select(col("b").bin.encode(BinaryEncoding.Hex).alias("hex"),
                      col("b").bin.startsWith("be").alias("be"),
                      col("b").bin.endsWith("ub").alias("ub"),
                      col("b").bin.contains("ea").alias("ea"),
                      col("b").bin.size.alias("n"))
    check r.toList("hex", string) == @["62656172", "637562"]
    check r.toList("be", bool) == @[true, false]
    check r.toList("ub", bool) == @[false, true]
    check r.toList("ea", bool) == @[true, false]
    check r.toList("n", int) == @[4, 3]
    let back = r.select(col("hex").cast(Binary).bin.decode(BinaryEncoding.Hex))
    check back.toList("hex", string) == @["bear", "cub"]
    let b64 = df.select(col("b").bin.encode(BinaryEncoding.Base64))
    check b64.toList("b", string) == @["YmVhcg==", "Y3Vi"]
    check newDataFrame(series("s", @["hi"])).select(col("s").str.encode(BinaryEncoding.Base64)).toList("s", string) == @["aGk="]

  test "bitwise":
    let df = newDataFrame(series("f", @[0b0110, 0b0011]))
    let r = df.select(col("f").bitwiseCountOnes.alias("ones"),
                      col("f").bitwiseTrailingZeros.alias("tz"),
                      col("f").bitwiseLeadingZeros.alias("lz"))
    check r.toList("ones", int) == @[2, 2]
    check r.toList("tz", int) == @[1, 0]
    check r.toList("lz", int) == @[61, 62]
    let a = df.select(col("f").bitwiseAnd.alias("and"), col("f").bitwiseOr.alias("or"),
                      col("f").bitwiseXor.alias("xor"))
    check a.toList("and", int) == @[2]
    check a.toList("or", int) == @[7]
    check a.toList("xor", int) == @[5]
    expect PolarsError:
      discard newDataFrame(series("s", @["x"])).select(col("s").bitwiseCountOnes)
