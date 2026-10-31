## Needs Datamancer: `nimble install datamancer`.
import std/[unittest, options]
import pkg/datamancer
import nanuq, nanuq/[datasets, datamancer]

suite "datamancer interop":
  test "penguins without nulls":
    let dm = penguins().dropNulls.toDatamancer
    check dm.len == 333
    check dm.getKeys == @["species", "island", "bill_length_mm", "bill_depth_mm",
                          "flipper_length_mm", "body_mass_g", "sex", "year"]
    check dm["body_mass_g"].kind == colInt
    check dm["bill_length_mm"].kind == colFloat
    check dm["species"].kind == colString
    check dm["species", 0, string] == "Adelie"

  test "nulls become null values in object columns":
    let dm = penguins().toDatamancer
    check dm.len == 344
    check dm["body_mass_g"].kind == colObject
    var nulls = 0
    for v in dm["body_mass_g"].toTensor(Value):
      if v.kind == VNull: inc nulls
    check nulls == 2
    check dm.drop_null("body_mass_g").len == 342
    check dm["species"].kind == colString

  test "unsigned integers become int":
    let counts = penguins().lazy.groupBy(col("species"))
      .agg(col("species").count.alias("n")).sort("species").collect
    check counts.dtype("n") == UInt32
    let dm = counts.toDatamancer
    check dm["n"].kind == colInt
    check dm["n", 0, int] == 152

  test "round trip":
    let df = newDataFrame(
      series("i", [some 1, none int, some 3]),
      series("f", [1.5, 2.5, 3.5]),
      series("b", [true, false, true]),
      series("s", [some "x", some "y", none string]),
    )
    let back = df.toDatamancer.fromDatamancer
    check back.shape == (3, 4)
    check back.columns == @["i", "f", "b", "s"]
    for c in ["i", "f", "b", "s"]:
      check back.dtype(c) == df.dtype(c)
      check back.nullCount(c) == df.nullCount(c)
    check back.toList("i", Option[int]) == @[some 1, none int, some 3]
    check back.toList("s", Option[string]) == @[some "x", some "y", none string]

  test "Datamancer frames built in Nim":
    var dm = toDf({"x": @[1, 2, 3], "y": @["a", "b", "c"]})
    dm["k"] = 7
    let df = dm.fromDatamancer
    check df.shape == (3, 3)
    check df.toList("k", int) == @[7, 7, 7]

  test "mixed object column raises":
    let dm = toDf({"m": @[%~ 1, %~ "a"]})
    check dm["m"].kind == colObject
    expect NanuqError:
      discard dm.fromDatamancer
