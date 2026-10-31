import std/unittest
import nanuq, nanuq/datasets

suite "datasets":
  test "penguins shape and columns":
    let df = penguins()
    check df.shape == (344, 8)
    check df.columns == @["species", "island", "bill_length_mm", "bill_depth_mm",
                          "flipper_length_mm", "body_mass_g", "sex", "year"]

  test "penguins nulls and dtypes":
    let df = penguins()
    check df.nullCount("body_mass_g") == 2
    check df.nullCount("sex") == 11
    check df.dtype("body_mass_g") == Int64
    check df.dtype("bill_length_mm") == Float64
    check df.dtype("species") == String
    check df["species", 0, string] == "Adelie"
    check df["sex", 3, Option[string]].isNone
