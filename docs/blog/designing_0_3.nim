import nimib
import std/os
import ../nanuqtheme

nbInit
nb.title = "Designing Nanuq 0.3"
# dated slug for the dev log (module names can't start with a digit)
nb.doc.filename = nb.doc.filename.parentDir / "2026-10-31-designing-0-3.html"
nb.useNanuqTheme(
  titleHtml = "Designing Nanuq <em>0.3</em>",
  eyebrow = "Nanuq dev log · 31 October 2026",
  epigraph = "Dates, strings, Parquet and categoricals: every API choice 0.3 had to make, the options, and what we picked.",
  meta = "API design · planned, not implemented yet · rendered with nimib",
  summary = "The API decisions behind Nanuq 0.3: temporal types, the str and dt namespaces, Parquet, errors and categoricals.",
)

nbText: """
Nanuq 0.3 brings dates and times, string expressions, Parquet and IPC, typed errors,
`glimpse` and `describe`, and categoricals. Before writing any of it, we wrote the
release's explainer post first, a recap of the 2026 cycling season, and listed every
API choice the story forced. This post is that list: for each choice, the options we
weighed and the one we picked.

Nothing here is implemented yet, so the code below is shown, not run. Two rules from
0.2 guide every choice:

- a closed set of option values is a pure enum with Polars' names, never a string;
- a cast target is a Nim type: `cast(int32)`, not `cast(Int32)`.

Breaking changes are fine: Nanuq has no users to break yet.
"""

nbText: """
## 1. Temporal types, the decision that matters most

Every temporal feature in 0.3 (parsing, the `dt` namespace, intervals, time zones,
reading values back into Nim) depends on how Polars' four temporal dtypes map to Nim
types. Polars has `Date` (a calendar day), `Datetime(timeUnit, timeZone)`,
`Duration(timeUnit)` and `Time` (a time of day). Nim's std/times does not cover what a
dataframe library needs:

- **No calendar date.** There is no `Date` type, only `DateTime`, which always carries
  a time and a zone. A birth date has to pretend to be midnight UTC.
- **No time of day.** std/times' `Time` is an *instant*, the opposite of Polars'
  `Time`. The same word means two different things.
- **Two time zones.** `local()` and `utc()`. Named zones such as "Europe/Rome" need
  the third-party `timezones` package.
- **`Duration` versus `TimeInterval`.** `4.minutes` builds a `TimeInterval`, not a
  `Duration`, an easy trap.
- **Style insensitivity.** To Nim, `Datetime` *is* `DateTime`. So the 0.2 pattern of
  DataType constants named after Polars (`Int64`, `String`) breaks: constants called
  `Datetime`, `Duration` and `Time` would clash with std/times in any program that
  imports both.

| Option | Date | Datetime | Duration | Time of day | Verdict |
|---|---|---|---|---|---|
| **std/times plus two small Nanuq types** | Nanuq `Date` | std/times `DateTime` | std/times `Duration` | Nanuq `TimeOfDay` | **Picked** |
| std/times only | `DateTime` at midnight UTC | `DateTime` | `Duration` | none | A date and a datetime look the same in Nim |
| Nanuq types for all four | `Date` | `PlDatetime` | `PlDuration` | `PlTime` | Users convert to std/times for any Nim-side work |
| Polars-named constants, as in 0.2 | `Date` | `Datetime` | `Duration` | `Time` | Clashes with std/times |

So Nanuq reuses std/times where it is good (`DateTime`, `Duration`, `TimeInterval`) and
fills its gaps with two small types: `Date` (days since 1970) and `TimeOfDay`. Both
convert to and from `DateTime`. Time zone names live inside Polars: a zoned column
prints with its zone, and its values come out in Nim as UTC `DateTime`s.

All four types are cast targets, with Polars' parameters as named arguments.
`TimeUnit` is a pure enum with Rust's names, and `DataTypeKind` gains `Date`,
`Datetime`, `Duration` and `Time` (safe there, because the enum is pure):
"""

nbCodeSkip:
  col("born").cast(Date)
  col("start").cast(DateTime, timeUnit = Milliseconds, timeZone = "Europe/Rome")
  col("gap_ms").cast(Duration, timeUnit = Milliseconds)

  lit(date(2026, 7, 4))                                # Date
  lit(dateTime(2026, mJul, 4, 13, 10, zone = utc()))   # Datetime[μs, UTC]
  lit(initDuration(minutes = 4, seconds = 23))         # Duration[μs], not 4.minutes

  assert df.schema["born"] == Date
  let born = df.toList("born", Date)                    # seq[Date]

nbText: """
## 2. Parsing and formatting dates

**Format strings use chrono codes**, as in Polars: `"%d %B %Y"`. They go straight to
Rust, and every Polars example applies. Translating Nim's `"d MMMM yyyy"` patterns
would be lossy and would leave two syntaxes to keep in sync.

**Parsing keeps all of Polars' names**: `str.toDate`, `str.toDatetime`, `str.toTime`,
and `str.strptime`, which takes a Nim type like `cast` does. The options are named
arguments with Polars' defaults (`strict = true`, `exact = true`, `cache = true`). With
`strict`, a bad row raises a `ComputeError` (section 6). CSV gets
`tryParseDates = false`.
"""

nbCodeSkip:
  col("born").str.toDate("%d %B %Y")
  col("born").str.strptime(Date, "%d %B %Y", strict = false)   # bad rows become null
  col("start").str.toDatetime("%Y-%m-%d %H:%M", timeZone = "Europe/Rome")

nbText: """
**Formatting** is `dt.toString(format)`, with `dt.strftime` as an alias. Durations have
two built-in formats, ISO (`PT4M23S`) and Polars' own (`4m 23s`). That is a closed
set, so it becomes the enum `DurationFormat.Iso` / `DurationFormat.Polars`.

## 3. Intervals and time zones

Polars spells intervals as strings: `"1d"`, `"2w"`, `"1mo"`, `"3d12h"`, `"1bd"`
(business day), `"1i"` (index count). `"1mo"` is calendar-aware: January 31 plus one
month is February 28.

| Option | Example | Verdict |
|---|---|---|
| **std/times `TimeInterval`, plus a string overload** | `dt.offsetBy(1.months)`, `offsetBy("1bd")` | **Picked.** Type-checked and calendar-aware like Polars; strings cover what Nim can't express |
| Polars strings only | `offsetBy("1mo")` | Typos only fail at run time |
| std/times `Duration` | `initDuration(days = 1)` | No months or years |
| A Nanuq `Interval` type | `1.mo` | A third time type next to two in std/times |

`dateRange(start, stop, interval = 1.days, closed = ClosedWindow.Both)` returns an
expression, used inside `select`. There is no `eager` flag, because a frame is one
`select` away.

Time zones are IANA names, an open set, so they stay strings. `dt.convertTimeZone`
moves the clock and `dt.replaceTimeZone` relabels it. Their `ambiguous` and
`nonExistent` options are pure enums.

## 4. The `str` and `dt` namespaces

`col("rider").str.toUppercase` and `col("born").dt.year` read exactly like Polars.
`str` and `dt` return a small `distinct Expr` wrapper, so names never clash between
namespaces (`str.len` and, later, `list.len`). Flat overloads on `Expr` would be
shorter, but they break as soon as the list namespace arrives.

Names are Polars' in camelCase (`lenChars`, `stripChars`, `startsWith`, `replaceAll`,
`totalDays`). Patterns use Rust's regex syntax, which has no backreferences and no
lookaround. Literal matching is a named argument, as in Python:
`str.contains("Pogačar", literal = true)`.

**One scope cut:** `str.split`, `extractAll` and `extractGroups` return List or Struct
columns, which are not in 0.3. They arrive with those dtypes.

## 5. Parquet, IPC and CSV from a string

Rust's `ParquetCompression` carries a level inside some variants (`Zstd(level)`). A
pure enum can't, so we follow Python's shape instead:
`writeParquet(df, path, compression = Zstd, compressionLevel = 10)`. The read and scan
functions take named arguments like the 0.2 CSV options, and IPC mirrors Parquet.

`readCsv(path)` already takes a string, so CSV text needs another way in. We picked a
`Stream` overload, Nim's version of Python's `read_csv(io.StringIO(s))`. It has no
ambiguity with paths and works for any stream:
"""

nbCodeSkip:
  let season = readCsv(newStringStream(seasonCsv))
  season.writeParquet("season.parquet", compression = Zstd)
  let monuments = scanParquet("monuments/*.parquet").collect

nbText: """
## 6. Errors

Today every failure raises one `NanuqError`. 0.3 renames it to `PolarsError` and adds
Python's subtypes: `ColumnNotFoundError`, `ComputeError`, `DuplicateError`,
`InvalidOperationError`, `NoDataError`, `OutOfBoundsError`, `SchemaError`,
`SchemaFieldNotFoundError`, `ShapeError`, `StructFieldNotFoundError`, `SqlError`. Nim
picks the `except` branch by type, so a hierarchy is more idiomatic than one type with
a `kind` field.

IO failures raise Nim's own `IOError`, as Python Polars raises the built-in
`FileNotFoundError`. A Nanuq `IoError` would be the same identifier as `IOError` to Nim
anyway.
"""

nbCodeSkip:
  try:
    discard results.select(col("finish").str.toTime("%H:%M:%S"))
  except ComputeError as e:
    echo "smudged result sheet: ", e.msg

nbText: """
## 7. Inspection, config and a rename

- `glimpse` returns a string (`echo df.glimpse`), like `$df`. Python prints by default,
  but a print hidden in what looks like a getter is not Nim's style.
- `describe(percentiles = [0.25, 0.5, 0.75])` returns a DataFrame. Rust Polars dropped
  it, so we build it from expressions, the way Python does.
- Table printing gets `setTblRows(20)`-style setters and a scoped
  `withConfig(tblRows = 20): echo df` template, Nim's version of Python's
  `with pl.Config(...)`.
- **`toSeq` becomes `toList`.** With Nanuq imported, `toSeq(walkFiles("*.csv"))`
  stopped compiling, because overload resolution picked Nanuq's proc over the
  `sequtils` template. `toList` is Polars' name (`to_list`), so the rename also follows
  the naming rule.

## 8. Categoricals, moved into 0.3

Categoricals were planned for later. The explainer is full of small fixed sets
(Monuments, Grand Tours, jerseys), so they moved in. Polars has two dtypes. `Enum` has
a fixed list of categories and sorts in declaration order. `Categorical` is open.

The choice that makes this feel native: **a Nim enum is a Polars Enum.** The
categories are the enum's string values, in order. Sorting by race gives the season
order (Sanremo in March, Lombardia in October), not the alphabet. `toList` gives back
real enum values for a `case`:
"""

nbCodeSkip:
  type Monument = enum
    MilanoSanremo = "Milano-Sanremo"
    Ronde = "Ronde van Vlaanderen"
    Roubaix = "Paris-Roubaix"
    Liege = "Liège-Bastogne-Liège"
    Lombardia = "Il Lombardia"

  let ordered = monuments
    .withColumns(col("race").cast(Monument))
    .sort("race")
  for race in ordered.toList("race", Monument):
    case race
    of Roubaix: echo "cobbles"
    else: discard

nbText: """
For sets known only at run time there is `Enum(["Milano-Sanremo", ...])`, Python's
name (Nim's keyword is the lowercase `enum`). Open sets use `cast(Categorical)`. Recent
Polars no longer needs a global string cache, so Nanuq has none.

## What's next

Each section becomes an OpenSpec change, then the implementation, then the explainer
that started all this. If a choice here looks wrong to you, now is the cheapest time to
say so.
"""

nbSave
