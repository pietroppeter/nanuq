import std/[unittest, options, strutils, os]
import nanuq

suite "temporal values":
  test "Date and TimeOfDay":
    let d = date(2026, 7, 4)
    check $d == "2026-07-04"
    check d.year == 2026 and d.month == mJul and d.monthday == 4
    check date(1904, 7, 2) < d
    check d + 1 == date(2026, 7, 5)
    check date(2026, 7, 5) - d == 1
    check d.toDateTime.toDate == d
    check $timeOfDay(14, 3) == "14:03:00"
    check $timeOfDay(9, 0, 5, 500_000_000) == "09:00:05.5"
    check timeOfDay(14, 3).minute == 3
    expect ValueError:
      discard timeOfDay(24)

  test "series, dtypes and reading back":
    let at = dateTime(2026, mJul, 4, 13, 10, zone = utc())
    let df = newDataFrame:
      day: [date(2026, 7, 4), nil]
      t: [timeOfDay(14, 3), timeOfDay(0)]
      gap: [initDuration(minutes = 4, seconds = 23), initDuration(hours = 73)]
      at: [at, dateTime(1904, mJul, 2, zone = utc())]
    check $df.dtypes == "@[Date, TimeOfDay, Duration(Microseconds), DateTime(Microseconds)]"
    check df.schema["day"] == Date
    check df.schema["at"] == DateTime
    check df.schema["gap"] == Duration
    check df.schema["t"] == TimeOfDay
    check df.toList("day", Option[Date]) == @[some(date(2026, 7, 4)), none(Date)]
    check df.toList("t", TimeOfDay) == @[timeOfDay(14, 3), timeOfDay(0)]
    check df.toList("gap", Duration)[0] == initDuration(minutes = 4, seconds = 23)
    check df.toList("at", DateTime)[0] == at
    check df["at", 1, DateTime].year == 1904
    check df["day", 1, Option[Date]].isNone
    expect InvalidOperationError:
      discard df.toList("day", DateTime)

  test "time units and zones":
    let s = series("at", [dateTime(2026, mJul, 4, 13, 10, zone = utc())], timeUnit = Milliseconds,
                   timeZone = "Europe/Rome")
    let df = newDataFrame(s)
    check $df.dtype("at") == """DateTime(Milliseconds, "Europe/Rome")"""
    check df.dtype("at") == dataType(DateTime, Milliseconds, "Europe/Rome")
    check df.toList("at", DateTime)[0] == dateTime(2026, mJul, 4, 13, 10, zone = utc())
    expect ValueError:
      discard newDataFrame(series("x", [dateTime(2026, mJul, 4, zone = utc())], timeUnit = Seconds))

  test "literals and comparisons":
    let df = newDataFrame:
      day: [date(2026, 7, 4), date(2026, 7, 5)]
    check df.filter(col.day > date(2026, 7, 4)).height == 1
    check df.select((col.day - lit(date(2026, 7, 1))).dt.totalDays.alias("d")).toList("d", int) == @[3, 4]
    check newDataFrame().select(lit(initDuration(minutes = 4)).alias("x")).dtype("x") == Duration
    check newDataFrame().select(lit(timeOfDay(1)).alias("x")).toList("x", TimeOfDay) == @[timeOfDay(1)]

  test "casts":
    let df = newDataFrame(series("n", [0, 86_400_000_000]))
    check df.select(col.n.cast(DateTime)).toList("n", DateTime)[1] ==
      dateTime(1970, mJan, 2, zone = utc())
    check df.select(col.n.cast(DateTime).cast(Date)).toList("n", Date) ==
      @[date(1970, 1, 1), date(1970, 1, 2)]
    check $df.select(col.n.cast(DateTime, timeUnit = Milliseconds, timeZone = "UTC")).dtype("n") ==
      """DateTime(Milliseconds, "UTC")"""
    check df.select(col.n.cast(Duration)).toList("n", Duration)[1] == initDuration(days = 1)

suite "ranges, durations, intervals":
  test "intervals":
    check toPolarsInterval(1.months) == "1mo"
    check toPolarsInterval(1.years + 2.days + 3.hours) == "1y2d3h"
    check toPolarsInterval(-2.days) == "-2d"
    expect ValueError:
      discard toPolarsInterval(1.days - 2.hours)

  test "dateRange":
    let r = newDataFrame().select(dateRange(date(2026, 1, 31), date(2026, 4, 30), 1.months).alias("d"))
    check r.toList("d", Date) == @[date(2026, 1, 31), date(2026, 2, 28), date(2026, 3, 31),
                                   date(2026, 4, 30)]
    let w = newDataFrame().select(dateRange(date(2026, 1, 1), date(2026, 1, 15), "1w",
                                            closed = ClosedWindow.Left).alias("d"))
    check w.height == 2

  test "datetimeRange":
    let r = newDataFrame().select(datetimeRange(dateTime(2026, mJan, 1, zone = utc()),
                                                dateTime(2026, mJan, 1, 3, zone = utc()),
                                                1.hours, timeZone = "Europe/Rome").alias("t"))
    check r.height == 4
    check $r.dtype("t") == """DateTime(Microseconds, "Europe/Rome")"""

  test "duration":
    let df = newDataFrame:
      h: [73, 1]
      m: [56, 0]
    let d = df.select(duration(hours = col.h, minutes = col.m, seconds = 26).alias("d"))
    check d.toList("d", Duration)[0] == initDuration(hours = 73, minutes = 56, seconds = 26)
    check d.select(col.d.dt.totalSeconds).toList("d", int)[1] == 3626

suite "parsing":
  let df = newDataFrame:
    born: ["17 July 1993", "24 September 2006", "smudged"]

  test "toDate":
    expect PolarsError:
      discard df.select(col.born.str.toDate("%d %B %Y"))
    check df.select(col.born.str.toDate("%d %B %Y", strict = false)).toList("born", Option[Date]) ==
      @[some(date(1993, 7, 17)), some(date(2006, 9, 24)), none(Date)]

  test "toDatetime, toTime, strptime":
    let t = newDataFrame(series("s", ["2026-07-04 13:10", "2026-07-05 09:00"]))
    let r = t.select(col.s.str.toDatetime("%Y-%m-%d %H:%M", timeZone = "Australia/Adelaide"))
    check $r.dtype("s") == """DateTime(Microseconds, "Australia/Adelaide")"""
    check t.select(col.s.str.slice(11).str.toTime("%H:%M")).toList("s", TimeOfDay) ==
      @[timeOfDay(13, 10), timeOfDay(9)]
    check t.select(col.s.str.strptime(Date, "%Y-%m-%d %H:%M")).toList("s", Date)[0] == date(2026, 7, 4)
    check t.select(col.s.str.toDate("%Y-%m-%d", exact = false)).toList("s", Date)[1] == date(2026, 7, 5)

  test "tryParseDates in CSV":
    let path = "tests/data/tmp_dates.csv"
    writeFile(path, "day,at,clock\n2026-07-04,2026-07-04 13:10:00,14:03\n2026-07-05,2026-07-05 09:00:00,09:00\n")
    defer: removeFile(path)
    let a = readCsv(path, tryParseDates = true)
    check a.schema["day"] == Date
    check a.schema["at"] == DateTime
    check readCsv(path).schema["day"] == String

suite "dt namespace":
  let df = newDataFrame:
    at: [dateTime(2026, mJul, 4, 13, 10, 5, zone = utc()), dateTime(2024, mFeb, 29, zone = utc())]

  test "parts":
    proc ints(e: Expr): seq[int] = df.select(e.alias("r")).toList("r", int)
    check ints(col.at.dt.year) == @[2026, 2024]
    check ints(col.at.dt.month) == @[7, 2]
    check ints(col.at.dt.day) == @[4, 29]
    check ints(col.at.dt.hour) == @[13, 0]
    check ints(col.at.dt.minute) == @[10, 0]
    check ints(col.at.dt.second) == @[5, 0]
    check ints(col.at.dt.weekday) == @[6, 4]
    check ints(col.at.dt.ordinalDay) == @[185, 60]
    check ints(col.at.dt.quarter) == @[3, 1]
    check df.select(col.at.dt.isLeapYear).toList("at", bool) == @[false, true]
    check df.select(col.at.dt.date).toList("at", Date) == @[date(2026, 7, 4), date(2024, 2, 29)]
    check df.select(col.at.dt.time).toList("at", TimeOfDay)[0] == timeOfDay(13, 10, 5)

  test "formatting":
    check df.select(col.at.dt.toString("%d %B %Y")).toList("at", string) ==
      @["04 July 2026", "29 February 2024"]
    check df.select(col.at.dt.strftime("%H:%M")).toList("at", string)[0] == "13:10"
    let g = newDataFrame(series("g", [initDuration(minutes = 4, seconds = 23)]))
    check g.select(col.g.dt.toString(DurationFormat.Iso)).toList("g", string) == @["PT4M23S"]
    check g.select(col.g.dt.toString(DurationFormat.Polars)).toList("g", string) == @["4m 23s"]

  test "truncate and offsetBy":
    check df.select(col.at.dt.truncate(1.months).dt.date).toList("at", Date) ==
      @[date(2026, 7, 1), date(2024, 2, 1)]
    check df.select(col.at.dt.offsetBy(1.years).dt.date).toList("at", Date)[1] == date(2025, 2, 28)
    check df.select(col.at.dt.offsetBy("-1d").dt.date).toList("at", Date)[0] == date(2026, 7, 3)
    check df.select(col.at.dt.monthEnd.dt.date).toList("at", Date)[0] == date(2026, 7, 31)

  test "time zones and combine":
    let days = newDataFrame:
      day: [date(2026, 1, 20)]
      finish: [timeOfDay(14, 3)]
    let finish = col.day.dt.combine(col.finish).dt.replaceTimeZone("Australia/Adelaide")
    let cet = days.select(finish.dt.convertTimeZone("Europe/Paris").alias("cet"))
    check $cet.dtype("cet") == """DateTime(Microseconds, "Europe/Paris")"""
    check cet.select(col.cet.dt.time).toList("cet", TimeOfDay) == @[timeOfDay(4, 33)]
    check cet.toList("cet", DateTime)[0] == dateTime(2026, mJan, 20, 3, 33, zone = utc())

  test "totals":
    let g = newDataFrame(series("g", [initDuration(hours = 36)]))
    check g.select(col.g.dt.totalDays).toList("g", int) == @[1]
    check g.select(col.g.dt.totalDays(fractional = true)).toList("g", float) == @[1.5]
    check g.select(col.g.dt.totalHours).toList("g", int) == @[36]

suite "inspection":
  test "describe and glimpse with temporal columns":
    let df = newDataFrame:
      day: [date(2026, 7, 4), date(2026, 7, 6)]
      at: [dateTime(2026, mJul, 4, 13, 10, zone = utc()), dateTime(2026, mJul, 4, 14, 10, zone = utc())]
    let d = df.describe
    check d.dtype("day") == String
    check d.toList("day", Option[string])[2] == some("2026-07-05 00:00:00.000000")
    check "$ at  <datetime[μs]> 2026-07-04 13:10:00, 2026-07-04 14:10:00" in df.glimpse

suite "dates from parts":
  test "date with expressions":
    let df = newDataFrame:
      year: [1950, 1951]
      month: [1, 12]
    check df.select(date(col.year, col.month, 15).alias("d")).toList("d", Date) ==
      @[date(1950, 1, 15), date(1951, 12, 15)]
    check df.select(date(col.year, 1, 1).alias("d")).dtype("d") == Date
    expect PolarsError:
      discard df.select(date(col.year, 2, 30).alias("d"))
