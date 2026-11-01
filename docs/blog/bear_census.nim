import nimib
import std/[os, strutils]
import nanuq
import ../nanuqtheme

nbInit
nb.title = "The great polar bear census"
# dated slug for the dev log (module names can't start with a digit)
nb.doc.filename = nb.doc.filename.parentDir / "2026-10-31-bear-census.html"
nb.useNanuqTheme(
  titleHtml = "The great <em>polar bear</em> census",
  eyebrow = "Nanuq dev log · 31 October 2026",
  epigraph = "Watch out where the huskies go, and don't you eat that rusty data.",
  meta = "Nanuq 0.2 · Polars 0.55 · Nim " & NimVersion & " · rendered with nimib",
  summary = "A season of messy ranger logs from Svalbard, cleaned and reported with everything new in Nanuq 0.2.",
)

# nimib runs from docs/ (see nimib.toml); the census files live in blog/census, and
# the code below reads them with paths relative to that folder.
let siteDir = getCurrentDir()
setCurrentDir("blog" / "census")
# Same table layout as the py-polars run that wrote blog/census/expected.
putEnv("POLARS_FMT_MAX_ROWS", "25")
putEnv("POLARS_FMT_MAX_COLS", "12")
putEnv("POLARS_TABLE_WIDTH", "120")

var mismatches: seq[string]

proc check(name, got: string, prefixOnly = false) =
  ## Compares a block's output with what py-polars prints for the same steps
  ## (blog/census/expected.py wrote expected/<name>.txt).
  var want = readFile("expected" / name & ".txt").strip(leading = false)
  if prefixOnly: want = want.split(" for ")[0]
  if got.strip(leading = false) != want:
    mismatches.add name
    stderr.writeLine "census: output of " & name & " differs from py-polars:\n" &
      got & "\n--- expected ---\n" & want

template scene(name: string, body: untyped) =
  nbCode(body)
  check(name, nb.blk.NbCode.output)

template castErrorScene(name: string, body: untyped) =
  ## Which bad value a failed cast reports depends on which chunk of the
  ## column Polars checks first, so only the part before " for " is compared.
  nbCode(body)
  check(name, nb.blk.NbCode.output.split(" for ")[0], prefixOnly = true)

nbText: """
*This post was written before the code it shows. We drafted it while Nanuq 0.2 was
still being designed, used it to decide the API, and checked every output against
the same steps run in Python Polars. Now 0.2 is built and the page runs for real:
each output below comes from Nanuq, and the page build compares it with the Python
one.*

Every spring, the rangers of Svalbard radio in the polar bears they see, and someone
at base has to turn their notes into a report. This post follows one season of those
notes through everything new in Nanuq 0.2: data types and casts, joins and
concatenation, frame verbs, CSV reading options, conditional expressions, window
functions and column selectors. A spring's worth of field logs needs every one of them.

## Why anyone counts polar bears

Svalbard's polar bears are counted for real, and the real numbers are small. An aerial
survey in August 2015 estimated about 264 bears on the islands themselves, and about
973 including the pack ice to the north
([Aars et al. 2017](https://polarresearch.net/index.php/polar/article/view/2660)).
Every spring since the 1990s, from March to May, the Norwegian Polar Institute has
captured and marked bears, recording sex, weight, length and body condition, and it
counts maternity dens on islands such as Hopen and Kongsøya
([MOSJ](https://mosj.no/en/indikator/fauna/marine-fauna/polar-bear/)).

Our census is invented, but it is shaped like that work: five stations, four weeks of
spring, one row per station per week (the week is a plain number: date types come in a
later release). Each row has the bears seen, the cubs among them,
the weight of one bear weighed that week, whether it wore a collar, and the seals it
was seen eating.

## The first week

Week one came in from four stations. Ingrid saw "lots" of bears and couldn't weigh any
of them, so she wrote `?`.
"""

scene("s01_first_week"):
  let week1 = readCsv("data/logs/week_01.csv")
  echo week1

nbText: """
`bears` and `weight_kg` are strings: Polars doesn't guess that "lots" is a number or
that `?` means "don't know". Barentsburg left the weight empty, which already reads as
null.

## Reading the whole season

The logs are one file per week. Polars can read all of them lazily with one glob, and
0.2 adds the reading options from Polars' CSV reader: here, `?` is a null value, and
two columns get their type up front with `schemaOverrides`, which takes `DataType`
values just like `cast`. `bears` stays text for now; we'll come back to "lots".
"""

scene("s02_scan_glob"):
  try:
    discard scanCsv("data/logs/*.csv", nullValues = ["?"],
                    schemaOverrides = {"bears": String, "weight_kg": Float64}).collect
  except PolarsError as e:
    echo e.msg.splitLines[0]

nbText: """
It fails. In week two a fifth station joined: **Hopen**, a small island in the
southeast where bears den every winter. Its ranger, Magnus, also measures the sea ice,
so from week two the logs have an extra `ice_cm` column, and a glob needs every file
to have the same columns.

So read each week separately and stack them with a *diagonal* concat, which matches
columns by name and fills the missing ones with nulls.
"""

scene("s03_scan_concat"):
  var weeks: seq[LazyFrame]
  for week in 1..4:
    weeks.add scanCsv("data/logs/week_0" & $week & ".csv", nullValues = ["?"],
                      schemaOverrides = {"bears": String, "weight_kg": Float64})
  let season = concat(weeks, how = Diagonal)

  for name, t in season.collectSchema:
    echo name.alignLeft(15), t

nbText: """
Nothing has been read yet: `collectSchema` works out the result's types from the plan
alone.

## "Lots" is not a number

A cast is strict by default, as in Polars: if a single value can't be converted, the
query fails, and the error names the culprit. The target can be a plain Nim type.
"""

castErrorScene("s04_strict"):
  try:
    discard season.select(col("bears").cast(int)).collect
  except PolarsError as e:
    echo e.msg.splitLines[0]

nbText: """
A non-strict cast turns what it can't read into nulls. That's the honest reading of
"lots": there were bears, we don't know how many. Cubs fit in a `uint8`, and the
`1`/`0` collar column becomes a boolean.
"""

scene("s05_cast"):
  let log = season.cast({"bears": Int64, "cubs": UInt8, "collared": Boolean},
                        strict = false).collect
  echo log.dtypes
  echo "bear counts we couldn't read: ", log.nullCount("bears")

nbText: """
Two: Ingrid's "lots" and Kari's "many".

## Ola radios everything twice

Ola, at Ny-Ålesund, has a habit of radioing his report twice when the line is bad. Two
identical rows are one report, so `unique` drops the copy. `maintainOrder` keeps the
rows in the order they came in, and a row index gives each report a number.
"""

scene("s06_tidy"):
  let tidy = log.unique(maintainOrder = true).withRowIndex("report", offset = 1)
  echo "reports: ", log.height, " radioed, ", tidy.height, " after unique"
  echo tidy.select(col("report", "week", "station", "ranger", "bears")).tail(3)

nbText: """
`col` with several names selects several columns at once, new in 0.2.

## Who was on duty?

Twice a ranger forgot to write their name. Each station has one ranger, so the name
from the station's previous report is the right one. The obvious fix, a forward fill,
takes the name from the row above, and the row above belongs to another station.
Adding `.over("station")` makes the fill run within each station, a *window* in
Polars' terms.
"""

scene("s07_fill"):
  echo tidy
    .select(col("report", "station", "ranger"),
            col("ranger").fillNull(Forward).alias("naive"),
            col("ranger").forwardFill.over("station").alias("per_station"))
    .filter(col("ranger").isNull)

nbText: """
The naive fill would have put Ola in Barentsburg and Ingrid in Ny-Ålesund.

## Sanity checks

Adult male polar bears weigh roughly 300 to 600 kg and can reach 800; females are about
half that ([Norwegian Polar Institute](https://npolar.no/en/?p=30674)). Anything outside
150 to 800 kg is a typo, so we drop it to null. That's a conditional expression, and
in Nanuq you write it with `choose` and an ordinary Nim `if`. Without an `else`, the
value is null, as in Polars.

Two stations, Longyearbyen and Barentsburg, are towns, where a bear is a safety
matter; `isIn` flags them.
"""

scene("s08_sanity"):
  let filled = tidy.withColumns(col("ranger").forwardFill.over("station"))
  let checked = filled.withColumns(
    choose(if col("weight_kg").isBetween(150, 800): col("weight_kg")).alias("weight_kg"),
    col("station").isIn(["Longyearbyen", "Barentsburg"]).alias("near_people"))

  echo checked.filter(col("station") == "Ny-Alesund")
    .select(col("report", "station", "weight_kg", "near_people"))

nbText: """
Report 11 said 1420 kg. Ola meant 142.0, but we can't know that, so it's null now.

## Where are the stations?

Base keeps a small table of station coordinates. Joining it adds latitude and longitude
to every report. Each report should match at most one station, and `validate` checks
exactly that:
"""

scene("s09_join_validate"):
  let stations = readCsv("data/stations.csv")
  try:
    discard checked.join(stations, on = ["station"], how = Left, validate = ManyToOne)
  except PolarsError as e:
    echo e.msg.splitLines[0]

nbText: """
Someone typed Hornsund in twice. And is any station missing from the table? An *anti*
join keeps the reports that have no match:
"""

scene("s10_join_anti"):
  echo checked.join(stations, on = ["station"], how = Anti).select(col("station")).unique

nbText: """
Nobody added Hopen. Fine for now: a left join keeps Hopen's reports, with null
coordinates.

## Slim, solid or chonk

Time to name the bears' sizes. `choose` takes a whole `if`/`elif`/`else` chain, and
turns it into Polars' `when/then/otherwise`, so the order matters: the first true
branch wins. The null check comes first, because a comparison with null is null, which
isn't true, so without it every unweighed bear would fall through to "chonk".

Polar bears live mostly on seals. Ringed seals are the main prey, and one big bearded
seal is worth about ten ringed ones, so the log gets a column of ringed-seal
equivalents too.
"""

scene("s11_size"):
  let located = checked.join(stations.unique(maintainOrder = true), on = ["station"],
                             how = Left, validate = ManyToOne,
                             maintainOrder = MaintainOrderJoin.Left)
  let size = choose:
    if col("weight_kg").isNull: "unweighed"
    elif col("weight_kg") < 200: "slim"
    elif col("weight_kg") < 450: "solid"
    else: "chonk"

  let sized = located.withColumns(size.alias("size"),
                                  (col("ringed") + 10 * col("bearded")).alias("seal_eq"))
  echo sized.select(col("station", "weight_kg", "size", "ringed", "bearded", "seal_eq")).head(8)

nbText: """
A bare string in `choose` is a value. (In Python Polars, `then("slim")` would look for
a *column* named "slim", a classic surprise; Nanuq takes columns only through `col`.)

## Each bear against its station

Hornsund keeps weighing heavy bears. How heavy compared with Hornsund's usual? A mean
`over` the station gives every row its station's average, without collapsing the rows
the way `groupBy` would.
"""

scene("s12_over"):
  echo sized.filter(col("station") == "Hornsund").select(
    col("week"), col("weight_kg"),
    (col("weight_kg") - col("weight_kg").mean.over("station")).round(1).alias("vs_station"))

nbText: """
## Every number, per station

For the station summary we want the mean of every numeric column, apart from a few
that make no sense to average. Column selectors pick columns by type, and Nanuq uses
Nim's own type classes for it: `col(SomeNumber)` is every numeric column,
`col(SomeFloat)` every float column, `col(int, float)` exactly those types.
Averaging many columns at once would give them all the same name, so `name.suffix`
renames each one.
"""

scene("s13_selectors"):
  echo sized.groupBy(col("station"))
    .agg(col(SomeNumber).exclude("report", "week", "cubs", "ringed", "bearded", "lat", "lon")
           .mean.round(1).name.suffix("_mean"))
    .sort("station")

nbText: """
Hopen sees the most bears but weighs the lightest. That fits: Hopen is a denning
island, and the bears Magnus weighs are mostly mothers with cubs, who are about half a
male's size. A mother usually has two cubs, and four or five in a week is a busy
spring. Hornsund, meanwhile, is where the big males are.

The season's weights in three numbers:
"""

scene("s14_quantile"):
  echo sized.select(col("weight_kg").median.alias("median"),
                    col("weight_kg").quantile(0.9).alias("p90"),
                    col("weight_kg").std.round(1).alias("std"))

nbText: """
## The report for the Governor

Polar bears have been protected since the 1973 international agreement on their
conservation, signed in Oslo, and Svalbard's bear reports go to the Governor's office.
The Governor likes the heaviest bears first and the unknowns at the end: a sort by two
keys, with `nullsLast`.
"""

scene("s15_report"):
  let report = sized
    .sort(["weight_kg", "week"], descending = [true, false], nullsLast = [true])
    .select(col("week", "station", "ranger", "bears", "weight_kg", "size", "seal_eq"))
  echo report

nbText: """
The Governor's auditor checks three reports at random by radio. A seed makes the pick
repeatable, which matters on a page that is rebuilt on every change:
"""

nbCode:  # not compared: seeded samples differ between Polars versions
  echo report.sample(3, seed = 42)

nbText: """
(Python Polars, with the same seed, picks the same three reports in another order: a
seed makes a sample repeatable within one version of Polars, not across versions.)
"""

nbText: """
The office's spreadsheet is Norwegian, so the headers go Norwegian, the separator is a
semicolon, and decimals use a comma: all options of `writeCsv` in 0.2.
"""

scene("s17_norsk"):
  let norsk = report.rename({"week": "uke", "station": "stasjon", "bears": "isbjorner",
                             "weight_kg": "vekt_kg", "size": "storrelse",
                             "seal_eq": "sel_ekv"})
  norsk.writeCsv("governor.csv", separator = ';', decimalComma = true)
  echo readFile("governor.csv").splitLines[0..3].join("\n")
removeFile("governor.csv")

nbText: """
## Late ice, light cubs

One last table. Hopen's station has also logged its maternity dens for the past eleven
years: how many dens were found, the mean weight of the cubs when they first came out
in spring, and the day of the year the sea ice reached the island the autumn before.
Pregnant females need that ice to reach the island and den there.
"""

scene("s18_dens"):
  let dens = readCsv("data/dens.csv")
  let iceArrived = choose:
    if col("ice_day") < 335: "before December"
    else: "December or later"

  echo dens.withColumns(iceArrived.alias("ice_arrived"))
    .groupBy(col("ice_arrived"))
    .agg(col("year").len.alias("years"),
         col("dens").mean.round(1).alias("dens"),
         col("cub_kg").mean.round(2).alias("cub_kg"))
    .sort("ice_arrived", descending = true)

nbText: """
In years when the ice came late, there were fewer dens and the cubs were lighter.

These numbers are made up, but the pattern is real: on Hopen, later autumn sea ice has
gone with lighter mothers and cubs at den emergence
([Derocher et al. 2011](https://int-res.com/abstracts/meps/v441/p273-279)). The full
picture is less simple: Svalbard's bears have so far kept, and even improved, their
body condition while the ice declined, which researchers expect to change as the ice
keeps retreating.

## What's in 0.2

Everything on this page, in the order it appeared:

- reading options for CSV files (`nullValues`, `schemaOverrides`, ...) and lazy
  `scanCsv`, and writing options (`separator`, `decimalComma`, ...);
- `concat` (vertical, horizontal, diagonal) and `join` (inner, left, right, full, semi,
  anti, cross) with `validate`;
- data types and casts, strict or not;
- frame verbs: `unique`, `withRowIndex`, `tail`, `sample`, `rename`, `drop`, `slice`,
  `reverse`, and sorting by several keys with `nullsLast`;
- conditional expressions with `choose`, and `isBetween`, `isIn`, `round`;
- null filling strategies (`fillNull(Forward)`, `forwardFill`);
- window expressions with `over`, and `median`, `quantile`, `std`;
- column selectors: several names, Nim type classes, `exclude`, and `name.suffix`.
"""


setCurrentDir(siteDir)
nbSave
if mismatches.len > 0:
  quit "census: outputs differ from py-polars in: " & mismatches.join(", ")
