import std/[unittest, options]
import nanuq

proc daily(): DataFrame =
  newDataFrame(series("day", [date(2026, 1, 1), date(2026, 1, 2), date(2026, 1, 8),
                              date(2026, 2, 1), date(2026, 2, 3)]),
               series("rain", [1, 2, 3, 4, 5]),
               series("site", ["a", "b", "a", "a", "b"]))

suite "groupByDynamic":
  test "monthly windows":
    let r = daily().groupByDynamic("day", every = 1.months).agg(col("rain").sum)
    check r.toList("day", Date) == @[date(2026, 1, 1), date(2026, 2, 1)]
    check r.toList("rain", int) == @[6, 9]
  test "weekly windows with string interval and boundaries":
    let r = daily().groupByDynamic(col("day"), every = "1w", includeBoundaries = true,
                                   startBy = StartBy.DataPoint).agg(col("rain").sum)
    check "_lower_boundary" in r.columns
    check r.toList("rain", int)[0] == 3
  test "period and groupBy":
    let r = daily().groupByDynamic("day", every = 1.months, period = 14.days,
                                   groupBy = [col("site")]).agg(col("rain").sum)
      .sort(["site", "day"])
    check r.toList("site", string) == @["a", "a", "b", "b"]
    check r.toList("rain", int) == @[4, 4, 2, 5]

suite "rolling group-by":
  test "last 7 days":
    let r = daily().rolling("day", period = 7.days).agg(col("rain").sum.alias("week"))
    check r.toList("week", int) == @[1, 3, 5, 4, 9]
  test "string period, groupBy":
    let r = daily().rolling("day", period = "7d", groupBy = [col("site")])
      .agg(col("rain").sum.alias("week"))
    check r.height == 5

suite "joinAsof":
  let quakes = newDataFrame(series("t", [date(2026, 1, 3), date(2026, 1, 9), date(2026, 2, 2)]),
                            series("site", ["a", "a", "b"]))
  test "by and tolerance":
    let r = quakes.joinAsof(daily(), leftOn = "t", rightOn = "day", by = "site")
    check r.toList("rain", int) == @[1, 3, 2]
    let near = quakes.joinAsof(daily(), leftOn = "t", rightOn = "day",
                               strategy = AsofStrategy.Nearest)
    check near.toList("rain", int) == @[2, 3, 5]
    let tol = quakes.joinAsof(daily(), leftOn = "t", rightOn = "day", tolerance = 1.days)
    check tol.toList("rain", int) == @[2, 3, 4]
    let strict = quakes.joinAsof(daily(), leftOn = "t", rightOn = "day", tolerance = "12h",
                                 allowExactMatches = false)
    check strict.toList("rain", Option[int]) == @[none(int), none(int), none(int)]
  test "numeric keys":
    let a = newDataFrame(series("k", [1, 5, 10]))
    let b = newDataFrame(series("k", [0, 4, 9]), series("v", ["x", "y", "z"]))
    check a.joinAsof(b, on = "k").toList("v", string) == @["x", "y", "z"]
    check a.joinAsof(b, on = "k", tolerance = 0).toList("v", Option[string]) ==
      @[none(string), none(string), none(string)]
  test "needs keys":
    expect ValueError: discard quakes.joinAsof(daily())
