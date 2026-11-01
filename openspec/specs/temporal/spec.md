# temporal Specification

## Purpose
Dates, datetimes, durations and times of day: Nim values, constructors, parsing strings, and the `dt` namespace.

## Requirements

### Requirement: Temporal values
The API SHALL provide `Date` (`date(y, m, d)`) and `TimeOfDay` (`timeOfDay(h, m, s, ns)`),
and SHALL accept them and std/times' `DateTime` and `Duration` wherever Nim values build
columns or literals. `toList` and `df[c, i, T]` SHALL read them back, as `Option` for
nulls. `DateTime` values SHALL be stored and read back as UTC instants. `nanuq` SHALL
export `std/times`.

```nim
let df = newDataFrame:
  rider: ["Seixas", "Pogačar"]
  born: [date(2006, 9, 24), date(1998, 9, 21)]
  start: [timeOfDay(13, 10), timeOfDay(13, 12)]
  gap: [initDuration(minutes = 4, seconds = 23), initDuration()]
  finish: [dateTime(2026, mJul, 4, 17, 21, zone = utc()), nil]
echo df
echo df.filter(col.born > date(2000, 1, 1)).toList("rider", string)
echo df.toList("born", Date)[0].year, " ", df["finish", 1, Option[DateTime]].isNone
```

```text
shape: (2, 5)
┌─────────┬────────────┬──────────┬──────────────┬─────────────────────┐
│ rider   ┆ born       ┆ start    ┆ gap          ┆ finish              │
│ ---     ┆ ---        ┆ ---      ┆ ---          ┆ ---                 │
│ str     ┆ date       ┆ time     ┆ duration[μs] ┆ datetime[μs]        │
╞═════════╪════════════╪══════════╪══════════════╪═════════════════════╡
│ Seixas  ┆ 2006-09-24 ┆ 13:10:00 ┆ 4m 23s       ┆ 2026-07-04 17:21:00 │
│ Pogačar ┆ 1998-09-21 ┆ 13:12:00 ┆ 0µs          ┆ null                │
└─────────┴────────────┴──────────┴──────────────┴─────────────────────┘
@["Seixas"]
2006 true
```

#### Scenario: Round trip
- **WHEN** a column built from `[date(2026, 7, 4), nil]` is read with `toList(df, c, Option[Date])`
- **THEN** the result is `@[some(date(2026, 7, 4)), none(Date)]`

#### Scenario: Out of range
- **WHEN** `timeOfDay(24)` is called
- **THEN** `ValueError` is raised

#### Scenario: Wrong reader
- **WHEN** a Date column is read with `toList(df, c, DateTime)`
- **THEN** `InvalidOperationError` is raised

### Requirement: Temporal ranges and durations
`dateRange(start, stop, interval = "1d", closed = ClosedWindow.Both)` and
`datetimeRange(..., timeUnit, timeZone)` SHALL return expressions. `interval` SHALL be
a Polars interval string or a `TimeInterval`, converted by `toPolarsInterval`, which
raises `ValueError` on mixed signs. `duration(weeks, days, hours, ..., nanoseconds)`
SHALL build a Duration from ints or expressions.

```nim
let months = newDataFrame().select(dateRange(date(2026, 1, 31), date(2026, 4, 30), 1.months).alias("day"))
echo months.toList("day", Date)
echo toPolarsInterval(1.years + 2.days)
let gaps = newDataFrame:
  h: [73, 0]
  m: [56, 4]
echo gaps.select(duration(hours = col.h, minutes = col.m, seconds = 26).alias("gap"))
```

```text
@[2026-01-31, 2026-02-28, 2026-03-31, 2026-04-30]
1y2d
shape: (2, 1)
┌───────────────┐
│ gap           │
│ ---           │
│ duration[μs]  │
╞═══════════════╡
│ 3d 1h 56m 26s │
│ 4m 26s        │
└───────────────┘
```

#### Scenario: Calendar steps
- **WHEN** `dateRange(date(2026, 1, 31), date(2026, 4, 30), 1.months)` is selected
- **THEN** the dates are the last days of January to April

#### Scenario: Half-open range
- **WHEN** `dateRange(date(2026, 1, 1), date(2026, 1, 15), "1w", closed = ClosedWindow.Left)` is selected
- **THEN** the result has 2 rows

#### Scenario: Mixed signs
- **WHEN** `toPolarsInterval(1.days - 2.hours)` is called
- **THEN** `ValueError` is raised

### Requirement: Parsing strings
`e.str` SHALL provide `strptime(T, format, strict = true, exact = true, cache = true)`
for `T` in `Date`, `DateTime` and `TimeOfDay`, and the shorthands `toDate(format)`,
`toDatetime(format, timeUnit, timeZone, ambiguous)` and `toTime(format)`. Formats SHALL
use chrono's codes; an empty format SHALL let Polars infer it. A strict parse SHALL
raise `PolarsError` when a value does not match; a non-strict one SHALL give null.
`exact = false` SHALL allow the format to match part of the string.

```nim
let df = newDataFrame:
  born: ["17 July 1993", "24 September 2006", "smudged"]
echo df.select(col.born.str.toDate("%d %B %Y", strict = false))
```

```text
shape: (3, 1)
┌────────────┐
│ born       │
│ ---        │
│ date       │
╞════════════╡
│ 1993-07-17 │
│ 2006-09-24 │
│ null       │
└────────────┘
```

#### Scenario: Strict failure
- **WHEN** `str.toDate("%d %B %Y")` runs over a value "smudged"
- **THEN** `PolarsError` is raised

#### Scenario: Zoned datetimes
- **WHEN** `str.toDatetime("%Y-%m-%d %H:%M", timeZone = "Australia/Adelaide")` is selected
- **THEN** the dtype is `datetime[μs, Australia/Adelaide]`

### Requirement: Date and time parts
`e.dt` SHALL return a `DtNameSpace` with `year`, `isoYear`, `quarter`, `month`, `week`,
`weekday` (Monday 1 to Sunday 7), `day`, `ordinalDay`, `hour`, `minute`, `second`,
`millisecond`, `microsecond`, `nanosecond`, `date`, `time`, `isLeapYear`,
`daysInMonth`, `monthStart` and `monthEnd`, each returning an expression with Polars'
result dtype.

```nim
let df = newDataFrame:
  at: [dateTime(2026, mJul, 4, 13, 10, zone = utc()), dateTime(2024, mFeb, 29, zone = utc())]
echo df.select(col.at.dt.year.alias("y"), col.at.dt.weekday.alias("wd"),
               col.at.dt.ordinalDay.alias("od"), col.at.dt.date.alias("d"),
               col.at.dt.time.alias("t"), col.at.dt.isLeapYear.alias("leap"))
```

```text
shape: (2, 6)
┌──────┬─────┬─────┬────────────┬──────────┬───────┐
│ y    ┆ wd  ┆ od  ┆ d          ┆ t        ┆ leap  │
│ ---  ┆ --- ┆ --- ┆ ---        ┆ ---      ┆ ---   │
│ i32  ┆ i8  ┆ i16 ┆ date       ┆ time     ┆ bool  │
╞══════╪═════╪═════╪════════════╪══════════╪═══════╡
│ 2026 ┆ 6   ┆ 185 ┆ 2026-07-04 ┆ 13:10:00 ┆ false │
│ 2024 ┆ 4   ┆ 60  ┆ 2024-02-29 ┆ 00:00:00 ┆ true  │
└──────┴─────┴─────┴────────────┴──────────┴───────┘
```

#### Scenario: Parts of a datetime
- **WHEN** `dt.day` and `dt.hour` run over 2026-07-04 13:10
- **THEN** the results are 4 and 13

#### Scenario: Not temporal
- **WHEN** `dt.year` runs over a string column
- **THEN** `PolarsError` is raised when the query runs

### Requirement: Formatting temporal values
`dt.toString(format)` and its alias `dt.strftime(format)` SHALL format dates, datetimes
and times with chrono's codes. `dt.toString(DurationFormat.Iso)` and
`dt.toString(DurationFormat.Polars)` SHALL format durations as ISO 8601 or Polars'
short form.

```nim
let df = newDataFrame:
  at: [dateTime(2026, mJul, 4, 13, 10, zone = utc())]
  gap: [initDuration(minutes = 4, seconds = 23)]
echo df.select(col.at.dt.toString("%d %B %Y"), col.gap.dt.toString(DurationFormat.Iso).alias("iso"),
               col.gap.dt.toString(DurationFormat.Polars).alias("short"))
```

```text
shape: (1, 3)
┌──────────────┬─────────┬────────┐
│ at           ┆ iso     ┆ short  │
│ ---          ┆ ---     ┆ ---    │
│ str          ┆ str     ┆ str    │
╞══════════════╪═════════╪════════╡
│ 04 July 2026 ┆ PT4M23S ┆ 4m 23s │
└──────────────┴─────────┴────────┘
```

#### Scenario: Duration formats
- **WHEN** a 4 min 23 s duration is formatted with `DurationFormat.Iso` and `DurationFormat.Polars`
- **THEN** the results are "PT4M23S" and "4m 23s"

### Requirement: Temporal arithmetic
Subtracting dates or datetimes SHALL give a Duration. `dt` SHALL provide
`truncate(every)`, `round(every)`, `offsetBy(by)` (intervals as strings or
`TimeInterval`s), `timestamp(timeUnit)`, `castTimeUnit(timeUnit)`, and on durations
`totalDays` … `totalNanoseconds`, whole numbers unless `fractional = true`.

```nim
let df = newDataFrame:
  born: [date(2006, 9, 24), date(1998, 9, 21)]
  race: [date(2026, 3, 21), date(2026, 3, 21)]
echo df.select((col.race - col.born).dt.totalDays.alias("days"),
               col.born.dt.offsetBy(19.years).alias("turns_19"),
               col.race.dt.truncate(1.months).alias("month"))
```

```text
shape: (2, 3)
┌───────┬────────────┬────────────┐
│ days  ┆ turns_19   ┆ month      │
│ ---   ┆ ---        ┆ ---        │
│ i64   ┆ date       ┆ date       │
╞═══════╪════════════╪════════════╡
│ 7118  ┆ 2025-09-24 ┆ 2026-03-01 │
│ 10043 ┆ 2017-09-21 ┆ 2026-03-01 │
└───────┴────────────┴────────────┘
```

#### Scenario: Leap day
- **WHEN** 2024-02-29 is offset by `1.years`
- **THEN** the result is 2025-02-28

#### Scenario: Fractional totals
- **WHEN** `dt.totalDays(fractional = true)` runs over 36 hours
- **THEN** the result is 1.5

### Requirement: Time zones
`dt.replaceTimeZone(timeZone, ambiguous = Ambiguous.Raise, nonExistent =
NonExistent.Raise)` SHALL attach a zone to wall-clock times (or remove it with ""),
`dt.convertTimeZone(timeZone)` SHALL show the same instants in another zone, and
`dt.combine(time)` SHALL join a date and a time of day into a datetime.

```nim
let stage = newDataFrame:
  day: [date(2026, 1, 20)]
  finish: [timeOfDay(14, 3)]
let local = col.day.dt.combine(col.finish).dt.replaceTimeZone("Australia/Adelaide")
echo stage.select(local.alias("adelaide"), local.dt.convertTimeZone("Europe/Paris").alias("paris"))
```

```text
shape: (1, 2)
┌─────────────────────────────────┬────────────────────────────┐
│ adelaide                        ┆ paris                      │
│ ---                             ┆ ---                        │
│ datetime[μs,                    ┆ datetime[μs, Europe/Paris] │
│ Australia/Adelaide]             ┆                            │
╞═════════════════════════════════╪════════════════════════════╡
│ 2026-01-20 14:03:00 ACDT        ┆ 2026-01-20 04:33:00 CET    │
└─────────────────────────────────┴────────────────────────────┘
```

#### Scenario: Same instant
- **WHEN** 14:03 in Adelaide on 2026-01-20 is converted to Europe/Paris
- **THEN** the time is 04:33 and the value read back equals 03:33 UTC

#### Scenario: Unknown zone
- **WHEN** `dt.convertTimeZone("Mars/Olympus")` runs
- **THEN** `PolarsError` is raised

### Requirement: Dates from parts
`date(year, month, day)` SHALL build a Date column when at least one part is an
expression; each part SHALL be an integer expression or a number, as Polars' `date`.
Invalid dates (month 13, 30 February) SHALL raise when the query runs. With three
numbers `date` SHALL keep returning a `Date` value.

```nim
let seasons = newDataFrame:
  year: [1982, 1997, 2015]
  month: [12, 11, 11]
echo seasons.select(date(col.year, col.month, 15).alias("mid"))
echo date(2026, 2, 1)
```

```text
shape: (3, 1)
┌────────────┐
│ mid        │
│ ---        │
│ date       │
╞════════════╡
│ 1982-12-15 │
│ 1997-11-15 │
│ 2015-11-15 │
└────────────┘
2026-02-01
```

#### Scenario: Mixed parts
- **WHEN** `date(col.year, 1, 1)` runs on years 1950 and 1951
- **THEN** the result is the dates 1950-01-01 and 1951-01-01

#### Scenario: Invalid date
- **WHEN** `date(col.year, 2, 30)` runs
- **THEN** a `PolarsError` is raised
