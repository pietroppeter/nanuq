import std/unittest
import nanuq

suite "data types":
  test "constants, names and predicates":
    check $Int64 == "i64"
    check $String == "str"
    check $Boolean == "bool"
    check $UInt8 == "u8"
    check $Null == "null"
    check Int64 != Int32
    check UInt8.isNumeric and Float32.isNumeric and not String.isNumeric
    check Int8.isSignedInteger and not Int8.isUnsignedInteger
    check UInt64.isUnsignedInteger and UInt64.isInteger
    check Float64.isFloat and not Int64.isFloat
    check DataType(kind: DataTypeKind.Other, name: "date") == DataType(kind: DataTypeKind.Other, name: "date")
    check DataType(kind: DataTypeKind.Other, name: "date") != DataType(kind: DataTypeKind.Other, name: "time")

  test "dataType of Nim types":
    check dataType(int) == Int64
    check dataType(int64) == Int64
    check dataType(int8) == Int8
    check dataType(uint16) == UInt16
    check dataType(float) == Float64
    check dataType(float32) == Float32
    check dataType(bool) == Boolean
    check dataType(string) == String
    check not compiles(dataType(ref int))
    check not compiles(col("a").cast(ref int))

  test "dtype and schema":
    let df = newDataFrame(series("a", [1, 2]), series("b", ["x", "y"]))
    check df.dtype("a") == Int64
    check $df.dtype("a") == "i64"
    check df.dtypes == @[Int64, String]
    let s = df.schema
    var keys: seq[string]
    for k in s.keys: keys.add k
    check keys == @["a", "b"]
    check s["b"] == String
    expect PolarsError: discard df.dtype("nope")

  test "lazy schema does not run the query":
    let df = newDataFrame(series("a", [1, 2]), series("s", ["1", "x"]))
    # A strict cast that fails at run time: resolving the schema must not run it.
    let lf = df.lazy.withColumns((col("a") * 1.5).alias("c"), col("s").cast(Int64).alias("bad"))
    let s = lf.collectSchema
    check s["c"] == Float64
    check s["bad"] == Int64
    expect PolarsError: discard lf.collect

  test "cast named columns":
    let df = newDataFrame(series("a", [1, 2]), series("b", [1, 0]))
    let c = df.cast({"a": Int32, "b": Boolean})
    check c.dtype("a") == Int32
    check c.toList("a", int) == @[1, 2]
    check c.toList("b", bool) == @[true, false]

  test "cast with a Nim type":
    let df = newDataFrame(series("a", [1, 2]))
    check df.select(col("a").cast(float32)).dtype("a") == Float32
    check df.select(`cast`(col("a"), uint8)).dtype("a") == UInt8
    check df.cast(float64).toList("a", float) == @[1.0, 2.0]
    check df.cast(String).toList("a", string) == @["1", "2"]

  test "strict and non-strict casts":
    let df = newDataFrame(series("s", ["1", "x"]))
    expect PolarsError: discard df.select(col("s").cast(int))
    let r = df.select(col("s").cast(int, strict = false))
    check r.toList("s", Option[int]) == @[some(1), none(int)]
    let r2 = df.cast({"s": Int64}, strict = false)
    check r2.nullCount("s") == 1

  test "unmodelled dtypes cannot be cast to":
    expect PolarsError: discard col("a").cast(DataType(kind: DataTypeKind.Other, name: "date"))
