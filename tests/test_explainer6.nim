import std/[unittest, options, os, strutils]
import nanuq

suite "explainer needs (0.6)":
  let moves = newDataFrame(series("m", @["\x03\x04\x10\x11", "ab"], Binary))

  test "binary slicing and bytes":
    check moves.select(col("m").bin.get(1))["m", 0, int] == 4
    check moves.select(col("m").bin.get(lit(-1)))["m", 1, int] == ord('b')
    check moves.select(col("m").bin.get(9, nullOnOob = true)).toList("m", Option[int])[0].isNone
    check moves.select(col("m").bin.slice(2, 2).bin.encode(BinaryEncoding.Hex))["m", 0, string] == "1011"
    check moves.select(col("m").bin.head(1))["m", 1, string] == "a"
    check moves.select(col("m").bin.tail(1))["m", 1, string] == "b"

  test "binary cells keep zero bytes":
    let z = newDataFrame(series("b", @["a\x00b"], Binary))
    check z["b", 0, string] == "a\x00b"

  test "decimal keys and arithmetic":
    let d = newDataFrame(series("komi", @["6.5", "7.5", "6.5", "0.5"])).select(col("komi").str.toDecimal(1))
    check d.groupBy("komi").agg(len()).height == 3
    check d.select(col("komi").mode).height == 1
    check d.sort("komi")["komi", 0, string] == "0.5"
    check d.filter(col("komi") == lit(6.5).cast(Decimal(10, 1))).height == 2
    # `mod` on Decimal needs a newer Polars than the 0.55 crate (py-polars 2.1 has it):
    # cast to Float64 first
    check d.select((col("komi").cast(Float64) mod 1).alias("f")).toList("f", float) ==
      @[0.5, 0.5, 0.5, 0.5]
    check d.select(lit(6.25).cast(Decimal(10, 1)).alias("x")).dtype("x") == Decimal(10, 1)

  test "binary in mapElements":
    let r = moves.select(col("m").mapElements(proc (b: string): int = b.len))
    check r.toList("m", int) == @[4, 2]

  test "strings to integers":
    let df = newDataFrame(series("k", @["zz", "10", "?"]))
    check df.select(col("k").str.toInteger(base = 36, strict = false)).toList("k", Option[int]) ==
      @[some(1295), some(36), none(int)]
    expect PolarsError:
      discard df.select(col("k").str.toInteger(base = 36))

  test "uint64 above high(int64)":
    let big = 9223372036854775809'u64
    let s = series("u", @[1'u64, big])
    check s.dtype == UInt64
    let df = newDataFrame(s)
    check df.toList("u", uint64) == @[1'u64, big]
    check df.select(col("u").bitwiseXor).toList("u", uint64) == @[big xor 1]
    check df.select(col("u").bitwiseCountOnes)["u", 1, int] == 2
    let o = newDataFrame(series("u", [some(big), none(uint64)]))
    check o.toList("u", Option[uint64]) == @[some(big), none(uint64)]

  test "csv lines as they are":
    let path = getTempDir() / "nanuq_lines.txt"
    writeFile(path, "a \"quoted, line\nbad \xff byte\n")
    let df = readCsv(path, separator = '\x01', hasHeader = false, quoteChar = none(char),
                     encoding = CsvEncoding.Utf8Lossy, newColumns = ["line"])
    check df.columns == @["line"]
    check df["line", 0, string] == "a \"quoted, line"
    check "byte" in df["line", 1, string]
    removeFile path
