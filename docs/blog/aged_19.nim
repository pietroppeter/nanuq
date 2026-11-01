import nimib
import std/[os, strutils, streams, times, enumutils]
import nanuq
import ../nanuqtheme

nbInit
nb.title = "Aged 19"
# dated slug for the dev log (module names can't start with a digit)
nb.doc.filename = nb.doc.filename.parentDir / "2026-11-01-aged-19.html"
nb.useNanuqTheme(
  titleHtml = "Aged <em>19</em>",
  eyebrow = "Nanuq dev log · 1 November 2026",
  epigraph = "A teenager's season, and 130 years of the records he chased.",
  meta = "Nanuq 0.3 · Polars 0.55 · Nim " & NimVersion & " · rendered with nimib",
  summary = "Paul Seixas's 2026 season and the history of cycling's age and speed records, told with everything new in Nanuq 0.3.",
)

# nimib runs from docs/ (see nimib.toml); the data lives in blog/aged19, and the code
# below reads it with paths relative to that folder.
let siteDir = getCurrentDir()
setCurrentDir("blog" / "aged19")

var mismatches: seq[string]

proc check(name, got: string) =
  ## Compares a block's output with what py-polars prints for the same steps
  ## (blog/aged19/expected.py runs aged19.py and writes expected/<name>.txt).
  let want = readFile("expected" / name & ".txt").strip(leading = false)
  if got.strip(leading = false) != want:
    mismatches.add name
    stderr.writeLine "aged19: output of " & name & " differs from py-polars:\n" &
      got & "\n--- expected ---\n" & want

template scene(name: string, body: untyped) =
  nbCode(body)
  check(name, nb.blk.NbCode.output)

nbText: """
*This post was written before the code it shows. We drafted it while Nanuq 0.3 was
still being designed, first in Python Polars and then in Nim against the planned API,
and used it to decide that API. Now 0.3 is built and the page runs for real: each
output below comes from Nanuq, and the page build compares it with the Python one.*

Paul Seixas started the 2026 season as a 19-year-old in his second year as a pro. By
October he had won the Tour of the Basque Country, the Flèche Wallonne and Il
Lombardia, and finished fourth in his first Tour de France. This post follows his
season, and 130 years of the records he chased, through what is new in Nanuq 0.3:
dates, durations and time zones, string expressions, Parquet, categoricals, and a few
conveniences such as `glimpse`, `col.name` and a block syntax for small tables.

The data comes from Wikipedia (CC BY-SA): winner lists, stage winners, the Tour start
lists of all 113 editions, birth dates, race dates, the 2026 calendar and the Giro
standings. Facts and quotes are from [inrng](https://inrng.com), the best reading in pro cycling.
"""

scene "setup":
  setTblRows(12); setTblCols(10); setTblWidthChars(120); setFmtStrLengths(60)

nbText: """
Four display setters on one line, separated by semicolons. `setConfig(tblRows = 12,
tblCols = 10, tblWidthChars = 120, fmtStrLengths = 60)` does the same in one call, like
Python's `pl.Config(...)`, and `withConfig` (below) changes them for one block only.
"""

nbText: """
## The season in one table

The 2026 World Tour calendar is small enough to paste into a post as a string.
`readCsv` now takes a stream, so a string goes in through `newStringStream`, and
`tryParseDates` turns the ISO dates into `Date` columns. `glimpse` shows each column
on one line.
"""

scene "s01_glimpse":
  let season = readCsv(newStringStream(readFile("data/world_tour_2026.csv")),
                       tryParseDates = true)
  echo season.glimpse

nbText: """
`glimpse` shows the types but hides the shape of the season. Printing all 36 rows
needs more than the 12-row default, so `withConfig` lifts the limit for one block
only. The `days` column shows what one row can hide: a stage race is a single row, yet
a week or three of racing, with a winner every day.
"""

scene "s01_calendar":
  withConfig(tblRows = 40):
    echo season.select(col.race, col.start, col.winner,
                       ((col.end - col.start).dt.totalDays + 1).alias("days"))

nbText: """
## Who won what

In cycling a win is a win, and there are three kinds. A one-day race (Sanremo,
Flanders, Lombardia) has one winner. A stage race has a winner every day, and an
overall winner at the end: the leader of the General Classification (GC), the rider
with the lowest total time, who often wins no stage at all. So a rider's season is
counted in all three: one-day wins, stage wins and GC wins. Team time trials are won by a team, and one Vuelta stage was
cancelled by a hailstorm, so those stages have no individual winner.

The stage winners come from each stage race's Wikipedia table. `concat` stacks the
three kinds into one table of victories. The kind is a Nim enum, so the column is a
Polars `Enum`, and a loop over the enum writes one count per kind.
"""

scene "s02_wins":
  type Kind = enum
    OneDay = "one-day", GC = "GC", Stage = "stage"

  let stages = readCsv("data/stages_2026.csv", tryParseDates = true,
                       schemaOverrides = {"stage": String})
  let raceKind = choose:
    if col.start == col.end: $OneDay
    else: $GC
  let victories = concat([
    season.select(col.winner, col.race.str.replaceAll("–", "-"), raceKind.alias("kind")),
    stages.filter(col.winner.isNotNull)
      .select(col.winner, (col.race.str.replaceAll("–", "-") + " stage " + col.stage).alias("race"),
              lit($Stage).alias("kind")),
  ]).withColumns(col.kind.cast(Kind))

  var perKind: seq[Expr]
  for k in Kind:
    perKind.add (col.kind == $k).sum.alias($k)
  withConfig(fmtStrLengths = 40):
    echo victories.groupBy(col.winner)
      .agg(@[col.race.count.alias("wins")] & perKind &
           @[col.race.filter(col.kind != $Stage).str.join(", ").alias("races")])
      .filter(col.wins >= 6)
      .sort(["wins", "GC", "winner"], descending = [true, true, false])

nbText: """
Pogačar won 22 times: four one-day races, three GCs (Romandie, Suisse,
the Tour) and 15 stages. A Tour stage and a stage of the Renewi Tour count the same
here, which is why sites like ProCyclingStats also weigh wins with points. Two other
profiles stand out. Jonathan Milan won nine stages and nothing else, a sprinter's
season. Seixas has an all-rounder's mix in his second pro year: two one-day races (Flèche Wallonne and
Lombardia), the Basque Country GC and three of its six stages, the same six wins
as Van der Poel and Evenepoel.

## Every Monument winner since 1892

Five one-day races are called the Monuments: Milano-Sanremo, the Ronde van Vlaanderen,
Paris-Roubaix, Liège-Bastogne-Liège and Il Lombardia. They have had 580 winners, and
with race dates and birth dates attached that is a table worth keeping in a typed,
compressed file. Parquet is new in 0.3, both writing and scanning lazily.
"""

scene "s03_parquet":
  let monuments = readCsv("data/monuments.csv", tryParseDates = true)
    .join(readCsv("data/riders.csv", tryParseDates = true), on = ["wiki"], how = Left)
  monuments.writeParquet("monuments.parquet", compression = Zstd)

  let lazy = scanParquet("monuments.parquet")
  echo lazy.select(col.race.count.alias("rows"),
                   col.year.min.alias("first"), col.year.max.alias("last"),
                   col.date.nullCount.alias("no_date"),
                   col.born.nullCount.alias("no_birth_date")).collect

nbText: """
Fifteen editions have no date on Wikipedia, and two winners have no birth date. They
stay null, and every age below ignores them.

The race column is a small fixed set, which is what a Nim `enum` is for. Casting to
one makes a Polars `Enum` column whose categories are the enum's strings, in
declaration order. Sorting follows the season, Sanremo in March to Lombardia in
October, not the alphabet.
"""

scene "s03_enum":
  type Monument = enum
    MSR = "Milano-Sanremo"
    RVV = "Ronde van Vlaanderen"
    PR = "Paris-Roubaix"
    LBL = "Liège-Bastogne-Liège"
    IL = "Il Lombardia"

  let races = lazy.withColumns(col.race.cast(Monument)).collect
  echo races.filter(col.year == 2026).sort("race").select(col("race", "date", "winner", "nat"))

nbText: """
The honour roll, as Wikipedia prints it: one column per Monument, first and latest
win, and a rank that shares places on ties. There is no pivot. Each Monument column is
a conditional sum, and a Nim loop over the enum writes the five expressions, naming
each column after the enum symbol. `rank(Min)` gives tied riders the same place.
"""

scene "s03_roll":
  var perRace: seq[Expr]
  for m in Monument:
    perRace.add (col.race == $m).sum.alias(symbolName(m))
  let roll = races.groupBy(col.winner)
    .agg(@[col.nat.first, col.year.min.alias("first"), col.year.max.alias("latest")] &
         perRace & @[col.race.count.alias("total")])
    .withColumns(col.total.rank(Min, descending = true).alias("rank"))
    .sort(["total", "first"], descending = [true, false])
  withConfig(tblCols = 12):
    echo roll.select(col.rank, all().exclude("rank")).head(12)

nbText: """
## Gerbi or Seixas?

[inrng, after Lombardia](https://inrng.com/2026/10/lombardia-2026-review/): "Seixas becomes the youngest ever winner of Lombardia, pipping
Giovanni Gerbi who was also 20 when he won the inaugural edition in 1905." Both were
20, so years can't separate them. Subtracting two `Date` columns gives a `Duration`,
and `totalDays` settles it.
"""

scene "s04_gerbi":
  let age = (col.date - col.born).alias("age")
  echo races.filter(col.winner.isIn(["Giovanni Gerbi", "Paul Seixas"]))
    .select(col.year, col.winner, col.born, col.date, age, age.dt.totalDays.alias("days"))

nbText: """
159 days younger.

## The youngest, everywhere

The youngest winner of each Monument is a window: keep the rows whose age equals the
smallest age in their race. Then the youngest winners of all.
"""

scene "s05_youngest":
  let withAge = races.withColumns(age.dt.totalDays.alias("days")).dropNulls("days")
  echo withAge.filter(col.days == col.days.min.over("race"))
    .sort("race").select(col("race", "year", "winner", "days"))
  echo withAge.sort("days").head(5).select(col("race", "year", "winner", "days"))

nbText: """
Only three Monument winners were ever younger than Seixas, and the most recent of them
won in 1944.

## Teenagers at the Tour

[inrng's Tour preview](https://inrng.com/2026/07/tour-de-france-preview-2026/): Seixas is "the youngest rider to start the Tour de France since
1937". To check that, we need every starter, not only the winners. Wikipedia has a
start list for each of the 113 editions: 16,438 starters, with a birth date for 94% of
them (almost all since 1930; the early Tours are patchy). Join each starter with the
first day of the race, subtract, and sort.
"""

scene "s06_tour":
  let starters = readCsv("data/starters/starters.csv", tryParseDates = true,
                         schemaOverrides = {"no": String})
  let editions = readCsv("data/starters/editions.csv", tryParseDates = true)
  let ages = starters.filter(col.dns == 0)
    .join(editions.select(col.year, col.start_date), on = ["year"])
    .withColumns((col.start_date - col.born).dt.totalDays.alias("age"))
  echo ages.filter(col.year >= 1930).sort("age", nullsLast = true)
    .select(col("year", "name", "born", "age")).head(5)

nbText: """
The start lists say since 1931, not 1937: Fabio Battesini rode the 1931 Tour at 7,071
days old, 152 days younger than Seixas. Then the nulls speak. Before 1940, a few
starters per edition have no birth date on Wikipedia, and one of them may be the rider
inrng had in mind.
"""

scene "s06_nulls":
  echo ages.filter(col.year.isBetween(1931, 1939))
    .groupBy(col.year).agg(col.name.count.alias("starters"),
                           col.born.nullCount.alias("no_birth_date"))
    .sort("year")

nbText: """
Before 1930 teenagers were common: 43 starters under 20, the youngest Camille Fily in
1904 at 17 years and 50 days. Since then there have been six, and Seixas is the
youngest of them. He finished fourth.

## Faster than ever

Wikipedia lists every Tour's distance and winning time as text, such as `73h 56′ 26″`.
`str.extract` pulls out the numbers, the new `duration` expression builds a
`Duration`, and the average speed follows. Two lessons from real data come with it.
CSV inference reads the first rows, guesses integers for the distance and then
fails on `3660.5`, so the column gets a schema override. And some Tours have no time
at all. 1905 to 1912 were decided on points, and 1999 to 2005 have no winner since
Armstrong's results were struck out.
"""

scene "s07_speed":
  var tours = readCsv("data/tour_winners.csv", schemaOverrides = {"distance_km": Float64})

  proc raceTime(c: string): Expr =
    proc part(unit: string): Expr =
      col(c).str.extract(r"(\d+)" & unit, 1).cast(int64).fillNull(0)
    choose:
      if col(c).isNotNull: duration(hours = part("h"), minutes = part("′"), seconds = part("″"))

  tours = tours
    .withColumns(raceTime("time").alias("time"), raceTime("margin").alias("margin"))
    .withColumns((col.distance_km / (col.time.dt.totalSeconds / 3600)).round(3).alias("speed"))
  echo tours.sort("speed", descending = true, nullsLast = true).head(5)
    .select(col("year", "winner", "distance_km", "time", "speed"))

nbText: """
`totalSeconds` is an integer column, and since 0.3 `/` is a true division, as in Nim
and Python Polars: `totalSeconds / 3600` gives fractional hours. Before 0.3 it
truncated the way Rust Polars does; `div` is there when whole hours are what you want.

43.887 km/h is a record, but [inrng's Tour review](https://inrng.com/2026/07/tour-de-france-2026-review/) gives the record as 43.227 km/h. At 43.227 km/h,
73h 56′ 26″ covers 3,196 km, not the 3,245 km Wikipedia lists. Race reports confirm it:
the riders covered 3,197 km (the route was planned at 3,333 km), so the table's distance
is wrong, not the clock.
"""

scene "s07_check":
  echo tours.filter(col.year == 2026)
    .select((lit(43.227) * col.time.dt.totalSeconds / 3600).round(1).alias("km_at_43.227"))

nbText: """
## 4′ 23″

Polars prints 73h 56′ 26″ as `3d 1h 56m 26s`. Cycling writes time its own way, so the
post builds a formatter from expressions: integer division with `div` and `mod`, and
`format` to put the pieces together. Vingegaard won Paris-Nice by 4′ 23″, the fourth
largest margin ever (the three wider ones were all in the 1930s). Tour margins get
much smaller.
"""

scene "s08_gaps":
  proc gap(c: string): Expr =
    let s = col(c).dt.totalSeconds
    proc two(e: Expr): Expr = e.cast(string).str.zfill(2)
    choose:
      if s >= 3600: format("{}h {}′ {}″", s div 3600, two(s mod 3600 div 60), two(s mod 60))
      else: format("{}′ {}″", s div 60, two(s mod 60))

  echo tours.dropNulls("margin").sort("margin").head(5)
    .select(col.year, col.winner, gap("margin").alias("margin"), gap("time").alias("time"))
  let parisNice = newDataFrame:
    paris_nice: [initDuration(minutes = 4, seconds = 23)]
  echo parisNice.select(gap("paris_nice"))

nbText: """
## The same band every night

The Giro's general classification after every stage. The leader's row holds a total
time and everyone else's holds a gap (`+ 5' 22"`), so the gap is built with `choose`.
Vingegaard took the pink jersey on stage 14 and kept it. Behind him the band took a
while to settle: Eulálio first, then Gall, with Arensman third until Hindley took the
place on stage 19.
"""

scene "s09_giro":
  let gapToLeader = choose:
    if col.rank == 1: duration(seconds = 0)
    else: duration(minutes = col.time.str.extract(r"(\d+)'", 1).cast(int64).fillNull(0),
                   seconds = col.time.str.extract("(\\d+)\"", 1).cast(int64).fillNull(0))
  let giro = readCsv("data/giro_gc_2026.csv")
    .withColumns(col.date.str.toDate("%d %B %Y"), gapToLeader.alias("gap"))

  echo giro.filter(col.rank <= 3).sort(["stage", "rank"])
    .groupBy(col.stage, col.date).agg(col.rider.str.join(" / ").alias("podium"))
    .sort("stage").tail(10)
  echo giro.filter(col.rider.isIn(["Felix Gall", "Jai Hindley"]) and col.stage >= 12)
    .groupBy(col.rider)
    .agg(col.rank.min.alias("best"), col.rank.max.alias("worst"),
         gap("gap").last.alias("final_gap"))
    .sort("rider")

nbText: """
## Set your alarm

The season starts in Adelaide. [inrng's preview](https://inrng.com/2026/01/2026-tour-down-under-preview/) lists each stage's finish in local
time, CET and US Eastern, and points out that stage 1 is due at 2.03pm, not 2pm. With
`tryParseDates`, "14:03" becomes a time of day (`TimeOfDay` in Nim). `dt.combine`
joins it to the date, `replaceTimeZone` says it is Adelaide time, and
`convertTimeZone` checks inrng's arithmetic.
"""

scene "s10_alarm":
  let tdu = readCsv(newStringStream("""stage,date,finish,inrng_cet,inrng_est
Prologue,2026-01-20,20:30,11:00,05:00
1,2026-01-21,14:03,16:33,22:32
2,2026-01-22,15:02,05:32,23:32
4,2026-01-24,13:22,03:52,21:52
"""), tryParseDates = true)

  let finish = col.date.dt.combine(col.finish).dt.replaceTimeZone("Australia/Adelaide")
  let cet = finish.dt.convertTimeZone("Europe/Paris")
  let est = finish.dt.convertTimeZone("America/New_York")
  echo tdu.select(col.stage, cet.alias("cet"), (cet.dt.time == col.inrng_cet).alias("cet_ok"),
                  est.alias("est"), (est.dt.time == col.inrng_est).alias("est_ok"))

nbText: """
Stage 1's CET time should read 4.33am, not 4.33pm, and its US time is a minute off.
The prologue and the other stages check out.

## The smudged result sheet

Not every source writes dates the same way. A strict parse stops at the first odd row
and raises a specific error type, which the post catches. A lenient parse turns the
odd row into null.
"""

scene "s11_smudged":
  let smudged = newDataFrame:
    race: ["Paris-Roubaix", "Amstel Gold Race", "La Flèche Wallonne"]
    date: ["12 April 2026", "19 April 2026", "22/04/2026"]
  try:
    discard smudged.withColumns(col.date.str.toDate("%d %B %Y"))
  except InvalidOperationError as e:
    echo "InvalidOperationError - ", e.msg.splitLines[0]
  echo smudged.withColumns(col.date.str.toDate("%d %B %Y", strict = false))

nbText: """
## Finale: one season, one strip

[inrng](https://inrng.com/2026/10/lombardia-2026-review/) counted "only 49 days of racing" for Seixas this year, across World Tour and
smaller races. These tables can't recount that: they list winners, not start lists.
What they can show is the World Tour around him. `dateRange` gives one row per day of
2026, and a cross join keeps the days that fall between a race's start and end: the
racing days of the calendar, month by month. Next to them, the days each rider won
something: a one-day race or a stage.
"""

scene "s12_strip":
  let year2026 = newDataFrame().select(
    dateRange(date(2026, 1, 1), date(2026, 12, 31), 1.days).alias("day"))
  let days = year2026.join(season, how = Cross).filter(col.day.isBetween(col.start, col.end))
  let won = concat([
    season.filter(col.start == col.end).select(col.winner, col.start.alias("day")),
    stages.select(col.winner, col.date.alias("day")),
  ])
  echo days.groupBy(col.day.dt.month.alias("month")).agg(col.day.count.alias("race_days"))
    .join(won.groupBy(col.day.dt.month.alias("month")).agg(
            (col.winner == "Paul Seixas").sum.alias("seixas_wins"),
            (col.winner == "Tadej Pogačar").sum.alias("pogacar_wins")),
          on = ["month"], how = Left)
    .sort("month")
  echo days.select(col.day.count.alias("world_tour_race_days"),
                   col.day.nUnique.alias("calendar_days"))

nbText: """
Pogačar won the Tour, three Monuments and 15 stages, with wins in six straight months, March to August.
Seixas won a Monument at 20 years and 16 days, and finished fourth in his first Tour at
19. inrng closes its [Lombardia review](https://inrng.com/2026/10/lombardia-2026-review/) with the question everyone is asking: is the
goal now to dethrone Pogačar? Next season's data will tell.

## What this post used from Nanuq 0.3

- temporal columns: `Date`, `DateTime`, `Duration` and `TimeOfDay`, date arithmetic,
  the `dt` namespace (`totalDays`, `totalSeconds`, `month`, `combine`, `time`), the
  `duration` expression, `dateRange`, and time zones with `replaceTimeZone` and
  `convertTimeZone`;
- `tryParseDates` when reading CSV, `str.toDate` strict or lenient, and the typed
  `InvalidOperationError` a strict parse raises;
- string expressions: `str.replaceAll`, `str.extract`, `str.zfill`, the `str.join`
  aggregation, and `format`;
- categoricals: a Nim enum cast to a Polars `Enum`, sorted in declaration order;
- Parquet: `writeParquet` with Zstd compression and a lazy `scanParquet`, and
  `readCsv` from a stream;
- inspection and display: `glimpse`, the `setTbl*` setters and a scoped `withConfig`;
- small things that add up: `col.name`, the block syntax for `newDataFrame`,
  `Expr.filter` inside an aggregation, `Expr.nullCount`, `rank` with ties, and `/` as a
  true division.

The same analysis in Python Polars, which wrote the outputs this page is checked
against, is in [blog/aged19/aged19.py](https://github.com/pietroppeter/nanuq/blob/main/docs/blog/aged19/aged19.py).
"""

setCurrentDir(siteDir)
nbSave
if mismatches.len > 0:
  quit "aged19: outputs differ from py-polars in: " & mismatches.join(", ")
