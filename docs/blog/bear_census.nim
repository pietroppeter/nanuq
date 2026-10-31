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
  meta = "Polars 0.55 · Nim " & NimVersion & " · rendered with nimib",
  summary = "Cleaning up a messy field log with Nanuq 0.2's data types, schemas and casts.",
)

nbText: """
Nanuq 0.2 is under way, and its first piece is in: data types. Columns now have a
real Nim type value instead of a string, you can ask a lazy query for its schema
before running it, and you can `cast`. That sounds dry, so this post puts it to
work on the kind of data that needs it most: a messy field log.

*This uses the development version of Nanuq (wrapper library `0.2.0-dev`, built
from source); nothing here is released yet. It follows
[How Nanuq works](2026-10-27-how-nanuq-works.html).*

## The field log

Every evening, the rangers of four stations on Svalbard radio in what they saw.
Someone at base types it into a spreadsheet. Rangers are excellent at counting
bears and less excellent at filling in spreadsheets:
"lots" is not a number, `?` is not a weight, and one of them writes `1` and `0`
for yes and no.
"""

nbCode:
  let notes = """station,ranger,bears,cubs,weight_kg,collared,seals_eaten
Longyearbyen,Ingrid,2,1,412.5,1,3
Longyearbyen,Ingrid,lots,2,?,0,
Ny-Alesund,Ola,1,0,389.0,1,2
Ny-Alesund,Ola,3,2,451.2,0,5
Barentsburg,Sasha,0,0,,0,0
Barentsburg,Sasha,2,1,402.8,1,4
Hornsund,Kari,many,3,515.0,1,7
Hornsund,Kari,1,1,367.4,0,1
"""
  let path = getTempDir() / "bear_notes.csv"
  writeFile(path, notes)
  let raw = readCsv(path)

nbShow(raw)

nbText: """
## What did Polars make of it?

`dtype` now returns a `DataType`, and `schema` gives every column's type in order.
Constants are named as in Polars (`Int64`, `String`, ...), and `$` prints Polars'
short name.
"""

nbCode:
  for name, t in raw.schema:
    echo name.alignLeft(12), $t, (if t.isNumeric: "" else: "   <- not a number")

nbText: """
`bears` and `weight_kg` came in as strings, because "lots", "many" and `?` don't
parse as numbers. That's what the CSV reader should do: it never guesses that
"lots" means 7. `seals_eaten` survived as integers, with an empty cell read as
null.

## Strict casts complain

A cast is strict by default, as in Polars: if a single value can't be converted,
the whole query fails, and the error says which values were the problem. The target
can be a plain Nim type.
"""

nbCode:
  try:
    discard raw.select(col("bears").cast(int))
  except NanuqError as e:
    echo e.msg.splitLines[0]

nbText: """
## Non-strict casts shrug

With `strict = false`, values that don't convert become nulls instead. That's the
honest reading of "lots": we know there were bears, we don't know how many. Here we
also turn the `1`/`0` column into booleans and keep the cub count in a `uint8`,
since nobody has yet seen 256 cubs. Per-column casts take `DataType` values,
written with braces like a table.
"""

nbCode:
  let log = raw.cast({"bears": Int64, "weight_kg": Float64,
                      "collared": Boolean, "cubs": UInt8}, strict = false)
  echo log.dtypes
  echo "bear counts we couldn't read: ", log.nullCount("bears")

nbShow(log)

nbText: """
## Ask the plan before running it

The report we want per station: how many bears were counted, how heavy they are
on average, and how many seals went missing. Before running it, `collectSchema`
tells us what the result will look like. Polars resolves the types through the
whole plan without touching the data, so a typo or an unexpected type shows up
here, not halfway through a long query.
"""

nbCode:
  let report = log.lazy
    .groupBy(col("station"))
    .agg(
      col("bears").sum.alias("bears"),
      col("bears").isNull.sum.alias("uncounted"),
      col("weight_kg").mean.alias("mean_weight_kg"),
      col("seals_eaten").sum.alias("seals"),
      col("collared").sum.alias("collared"),
    )
    .sort("station")

  for name, t in report.collectSchema:
    echo name.alignLeft(15), t

nbText: """
Summing booleans counts the `true` values, and the count comes back as an unsigned
integer, which is what Polars does. Now run it:
"""

nbCode:
  let byStation = report.collect

nbShow(byStation)

nbText: """
Hornsund wins on both weight and seals (well fed, then), and two stations owe us a
proper count. Barentsburg's missing weight is skipped by `mean`. Each null reached the report as a null, not as a zero or a
made-up guess.

## Types at compile time, too

`cast` and `dataType` accept Nim types, so mistakes in the type itself are caught
by the compiler. There is no Polars dtype for a sequence of seals (not yet: lists
come in a later release), so this doesn't compile:
"""

nbCode:
  type Seal = object
    name: string
  echo dataType(uint8)
  echo compiles(col("snacks").cast(seq[Seal]))

nbText: """
## What's next

Data types are the foundation for the rest of 0.2: joins and concatenation, more
frame verbs (`drop`, `rename`, `unique`, ...), conditional expressions, column
selectors such as "all numeric columns", and CSV options such as schema overrides,
which will let `readCsv` cast while it reads. With those, the rangers' log could be
joined with a table of station coordinates, and the next post will probably do just
that.
"""

nbSave
