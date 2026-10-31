# Proposal

## Why

Nanuq 0.2 cannot hold a date. Every real table has one: a rider's birth date, a stage
date, a finishing time, a gap to the winner. The 0.3 explainer "Aged 19" is built on
them (age of a winner on race day, gaps in hours and minutes, finish times across time
zones), and the dev log "Designing Nanuq 0.3" names temporal types the critical item of
the release.

Nim's standard library makes this harder than in Python: `std/times` has `DateTime` and
`Duration`, but no date without a time, no time of day, only local and UTC zones, and a
`TimeInterval` (calendar steps such as `1.months`) next to `Duration` (exact lengths).
The design (dev log section 1) keeps the std/times types where they fit and adds two
small Nanuq types where they do not.

This change takes up the dates part of the BACKLOG.md entry "More dtypes". It is the
fifth change of the 0.3 release.

## What Changes

- **Data types**: `DataTypeKind` gains `Date`, `Datetime`, `Duration` and `Time`.
  Datetime and Duration carry a `timeUnit` (std/times' `TimeUnit`, limited to
  `Nanoseconds`, `Microseconds`, `Milliseconds`), and Datetime an optional `timeZone`
  (an IANA name). `$` gives Polars' names (`datetime[μs, Europe/Rome]`).
  `schema[c] == DateTime` matches any unit and zone.
- **Nim values**: `Date` (a `distinct int32` of days since 1970-01-01, with `date(y, m,
  d)`, `year`, `month`, `monthday`, `$`, `+`/`-` days and comparisons) and `TimeOfDay`
  (with `timeOfDay(h, m, s, ns)`), next to std/times' `DateTime` and `Duration`.
  `series`, block `newDataFrame`, `lit`, `toList`, `df[c, i, T]`, `fillNull` and the
  comparison operators accept them. `nanuq` exports `std/times`.
- **Casts**: `cast(Date)`, `cast(DateTime, timeUnit = Milliseconds, timeZone =
  "Europe/Rome")`, `cast(Duration)` and `cast(TimeOfDay)`.
- **Constructors**: `dateRange(start, stop, interval = "1d", closed =
  ClosedWindow.Both)` and `datetimeRange(...)` return expressions; `duration(weeks =
  ..., days = ..., hours = ..., ..., nanoseconds = ...)` takes ints or expressions.
  Intervals are Polars strings (`"1mo"`) or std/times `TimeInterval`s (`1.months`),
  converted by `toPolarsInterval`.
- **Parsing**: `str.strptime(T, format, strict, exact, cache)`, `str.toDate`,
  `str.toDatetime(format, timeUnit, timeZone, ambiguous)` and `str.toTime`, with chrono
  format codes. `readCsv` and `scanCsv` take `tryParseDates = false`.
- **The `dt` namespace** (a `distinct Expr`, like `str`): `year`, `isoYear`, `quarter`,
  `month`, `week`, `weekday`, `day`, `ordinalDay`, `hour`, `minute`, `second`,
  `millisecond`, `microsecond`, `nanosecond`, `date`, `time`, `isLeapYear`,
  `daysInMonth`, `monthStart`, `monthEnd`, `timestamp`, `castTimeUnit`,
  `toString`/`strftime` (a format string, or `DurationFormat.Iso`/`Polars` for
  durations), `truncate`, `round`, `offsetBy`, `convertTimeZone`,
  `replaceTimeZone(tz, ambiguous, nonExistent)`, `combine(time)` and
  `totalDays`…`totalNanoseconds(fractional = false)`.
- **Inspection**: `glimpse` and `describe` handle temporal columns.
- Polars features `temporal`, `dtype-date`, `dtype-datetime`, `dtype-duration`,
  `dtype-time`, `timezones`, `offset_by`, `range`, `month_start` and `month_end` (already
  compiled in by the string change) are used.

Not in this change: `groupByDynamic` and rolling windows, `dt.weekday` names,
business-day functions, `dt.epoch` variants beyond `timestamp`, `upsample`.

## Capabilities

### New Capabilities
- `temporal`: temporal values, constructors, parsing and the `dt` namespace.

### Modified Capabilities
- `data-types`: the four temporal kinds, time units and zones, temporal cast targets and
  the Nim type mapping.
- `csv-io`: `tryParseDates`.
- `native-bridge`: `NqTimeUnit`, `NqClosedWindow` and `NqDtOp` join the ordered enums;
  dtypes cross the ABI as an `NqDtypeSpec` struct.

## Differences from Polars

Expected differences from Polars' Rust and Python APIs:

- **Nim value types**: Python uses `datetime.date`, `datetime.datetime`,
  `datetime.timedelta` and `datetime.time`; Rust uses chrono. Nanuq uses std/times'
  `DateTime` and `Duration` plus its own `Date` and `TimeOfDay`.
- **DateTime values are instants**. A `DateTime` given to `series` or `lit` is stored as
  its UTC instant, and naive (no zone) unless `timeZone` is given. Values read back are
  UTC `DateTime`s, whatever the column's zone. Python keeps naive datetimes as wall-clock
  time and returns zone-aware ones in the column's zone.
- **Style insensitivity**: Nim cannot tell `Datetime` from `DateTime`, so the cast target
  and the `==` right-hand side are std/times' `DateTime`; `DataTypeKind.Datetime` names
  the kind. `col(DateTime)` selects only naive microsecond datetimes (an exact dtype);
  use a `DataType` for other units and zones.
- **Time units** reuse std/times' `TimeUnit` (`Milliseconds`, not `"ms"`); other values
  raise `ValueError`.
- **Intervals** accept std/times' `TimeInterval` (`1.months + 2.days`) next to Polars'
  strings; mixed signs raise `ValueError`.
- **`dateRange` and `datetimeRange`** return expressions only (Python's `eager = true` is
  `newDataFrame().select(...)`).
- **Enums for string options**: `ClosedWindow`, `Ambiguous` (`Raise`, `Earliest`,
  `Latest`, `Null`), `NonExistent` (`Null`, `Raise`) and `DurationFormat` (`Iso`,
  `Polars`) are pure enums; `Ambiguous.Null` must always be qualified.
- **`dt.toString`** takes `DurationFormat` for durations instead of the strings "iso"
  and "polars"; `strftime` is an alias, as in Python.
- **`describe`** shows datetime statistics with Polars' cast to string
  (`2026-07-05 00:00:00.000000`) and durations in Polars' format (`4m 23s`), where Python
  formats them itself.
- **Names** follow Polars in camelCase: `ordinal_day` → `ordinalDay`, `convert_time_zone`
  → `convertTimeZone`, `try_parse_dates` → `tryParseDates`.

## Impact

- `src/rust/src/lib.rs`: `NqDtypeSpec` replaces the dtype code in casts, selectors and
  schema overrides; temporal series, literals, ranges, `duration`, `strptime` and
  `nq_expr_dt` with `NqDtOp`.
- `src/nanuq/ffi.nim`, `src/nanuq.nim`: the declarations, `Date`, `TimeOfDay`, the
  temporal `DataType` fields, casts, constructors, parsing and `DtNameSpace`.
- `tests/test_temporal.nim` (new); README; BACKLOG "More dtypes" keeps only the
  remaining dtypes.
