import std/[unittest, options, strutils]
import nanuq

suite "glimpse":
  test "layout and quoting":
    let df = newDataFrame:
      rider: ["Pogačar", "Seixas", "Van der Poel"]
      wins: [22, 8, nil]
      pro: [true, false, true]
      race: ["Giro d'Italia", "Tour", "Vuelta"]
    check df.glimpse == """Rows: 3
Columns: 4
$ rider  <str> 'Pogačar', 'Seixas', 'Van der Poel'
$ wins   <i64> 22, 8, null
$ pro   <bool> True, False, True
$ race   <str> "Giro d'Italia", 'Tour', 'Vuelta'
"""

  test "truncation":
    var xs: seq[int]
    for i in 1 .. 100: xs.add i
    let long = repeat('x', 60)
    let df = newDataFrame(series(long, xs))
    let lines = df.glimpse(maxItemsPerColumn = 3).splitLines
    check lines[2] == "$ " & repeat('x', 49) & "… <i64> 1, 2, 3"

suite "describe":
  test "numeric, bool and string columns":
    let df = newDataFrame:
      rider: ["Pogačar", "Seixas", "Van der Poel"]
      wins: [22, 8, nil]
      pro: [true, false, true]
    let d = df.describe
    check d.columns == @["statistic", "rider", "wins", "pro"]
    check d.toList("statistic", string) ==
      @["count", "null_count", "mean", "std", "min", "25%", "50%", "75%", "max"]
    check d.dtype("wins") == Float64
    check d.dtype("rider") == String
    check d.toList("wins", Option[float])[0 .. 2] == @[some(2.0), some(1.0), some(15.0)]
    check d.toList("rider", Option[string]) ==
      @[some("3"), some("0"), none(string), none(string), some("Pogačar"), none(string),
        none(string), none(string), some("Van der Poel")]
    check d.toList("pro", Option[float])[3].isNone

  test "percentiles":
    let df = newDataFrame(series("a", [1, 2, 3]))
    check df.lazy.describe(percentiles = [0.1, 0.333, 0.9]).toList("statistic", string) ==
      @["count", "null_count", "mean", "std", "min", "10%", "33.3%", "90%", "max"]

  test "no columns":
    expect PolarsError:
      discard newDataFrame().describe

suite "display config":
  setup: resetConfig()
  teardown: resetConfig()

  test "setters":
    var xs: seq[int]
    for i in 1 .. 20: xs.add i
    let df = newDataFrame(series("n", xs))
    check "…" in $df
    setTblRows(-1)
    check "…" notin $df
    setTblRows(none(int))
    check "…" in $df
    setConfig(tblRows = 30)
    check "…" notin $df
    resetConfig()
    check "…" in $df

  test "withConfig restores, also after an exception":
    var xs: seq[int]
    for i in 1 .. 20: xs.add i
    let df = newDataFrame(series("n", xs))
    setTblRows(4)
    withConfig(tblRows = 30, fmtStrLengths = 5):
      check "…" notin $df
    check ($df).count('\n') == 11
    expect ValueError:
      withConfig(tblRows = 30):
        raise newException(ValueError, "boom")
    check ($df).count('\n') == 11
