import std/[options, unittest]
import nanuq
import pluginfixture

# A tiny plugin written against the plugin C ABI, built once for these tests.
let pluginLib = doubleItLib()

suite "expression plugins":
  test "registerPluginFunction calls the plugin on each column":
    let df = newDataFrame(series("x", [1.5, 2.0, 4.0]))
      .vstack(newDataFrame(series("x", @[none(float), some(-1.0)])))   # two chunks, a null
    let res = df.select(registerPluginFunction(pluginLib, "double_it", [col"x"], isElementwise = true))
    check res.columns == @["x"]
    check $res["x"].dtype == "Float64"
    check res["x"].toList(Option[float]) == @[some(3.0), some(4.0), some(8.0), none(float), some(-2.0)]

  test "the plugin's error message becomes a ComputeError":
    let df = newDataFrame(series("x", ["a", "b"]))
    expect ComputeError:
      discard df.select(registerPluginFunction(pluginLib, "double_it", [col"x"], isElementwise = true))

  test "plugins compose with other expressions, lazily":
    let df = newDataFrame(series("g", ["a", "a", "b"]), series("x", [1.0, 2.0, 3.0]))
    let res = df.lazy.groupBy("g").agg(
      registerPluginFunction(pluginLib, "double_it", [col"x"], isElementwise = true).sum.alias("s"))
      .sort("g").collect
    check res["s"].toList(float) == @[6.0, 6.0]
