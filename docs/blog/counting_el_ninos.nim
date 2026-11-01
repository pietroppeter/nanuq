import nimib
import std/[os, strutils, strformat, json, tables, times, xmltree]
import nanuq
import plotly/plotly_types except Color
import ../nanuqtheme
import el_nino/plots

nbInit
nb.title = "Counting El Niños"
# dated slug for the dev log (module names can't start with a digit)
nb.doc.filename = nb.doc.filename.parentDir / "2026-11-01-counting-el-ninos.html"
nb.useNanuqTheme(
  titleHtml = "Counting <em>El Niños</em>",
  eyebrow = "Nanuq dev log · November 2026",
  epigraph = "A warm patch of ocean, and the weather of the whole world.",
  meta = "Nanuq 0.4 · Polars 0.55 · Nim " & NimVersion & " · rendered with nimib",
  summary = "What El Niño is, how NOAA counts it, and what it does to rain in Peru and " &
            "to the temperature of the planet, told with everything new in Nanuq 0.4.",
)

# nimib runs from docs/ (see nimib.toml); the data lives in blog/el_nino, and the code
# below reads it with paths relative to that folder.
let siteDir = getCurrentDir()
setCurrentDir("blog" / "el_nino")

# ---------------------------------------------------------------------------
# Nim and Python in tabs. The Python side is el_nino.py, the same analysis in
# py-polars: its code is read from that file by cell id, and its outputs (text and
# Plotly figures) are the ones expected.py recorded in expected/. Every Nim output is
# checked against the Python one, and the page build fails if any differs.

proc cells(path: string): Table[string, string] =
  ## The code cells of a jupytext percent-format script, by their `# id:` line.
  for cell in readFile(path).split("\n# %%")[1 .. ^1]:
    if cell.startsWith(" [markdown]"): continue
    let lines = cell.strip(leading = false).splitLines
    result[lines[1].replace("# id: ", "")] = lines[2 .. ^1].join("\n").strip(chars = {'\n'})

proc definition(path, header: string): string =
  ## The source of one top-level definition (from `header` to the next one).
  let src = readFile(path).splitLines
  var start = -1
  for i, l in src:
    if start < 0 and l.startsWith(header): start = i
    elif start >= 0 and l.len > 0 and l[0] notin {' ', ')'} and not l.startsWith("#"):
      return src[start ..< i].join("\n").strip
  src[start .. ^1].join("\n").strip

let pyCells = cells("el_nino.py")
var mismatches: seq[string]

proc normalized(s: string): string =
  ## Nim prints a seq as @[...], Python a list as [...]; nothing else is touched.
  s.strip(leading = false).replace("@[", "[")

proc checkOutput(name, got: string) =
  let want = readFile("expected" / name & ".txt")
  if got.normalized != want.normalized:
    mismatches.add name
    stderr.writeLine "el_nino: output of " & name & " differs from py-polars:\n" &
      got & "\n--- expected ---\n" & want

proc pythonCode(code: string): string =
  "<pre><code class=\"language-python\">" & xmltree.escape(code) & "</code></pre>"

proc tabsHtml(nimSide, pySide: string): string =
  "<div class=\"nq-tabs\"><div class=\"nq-tablist\" role=\"tablist\">" &
    "<button class=\"nq-tab\" role=\"tab\" data-lang=\"nim\" aria-selected=\"true\">👑 Nim</button>" &
    "<button class=\"nq-tab\" role=\"tab\" data-lang=\"python\" aria-selected=\"false\">🐍 Python</button></div>" &
    "<div class=\"nq-panel\" data-lang=\"nim\">" & nimSide & "</div>" &
    "<div class=\"nq-panel\" data-lang=\"python\" hidden>" & pySide & "</div></div>"

template inTabs(pySide: string, body: untyped) =
  ## Renders the blocks `body` adds as the Nim tab, next to `pySide`.
  let first = nb.blocks.len
  body
  var nimSide = ""
  for i in first ..< nb.blocks.len:
    nimSide.add nb.render(nb.blocks[i])
  nb.blocks.setLen(first)
  nbRawHtml: tabsHtml(nimSide, pySide)

template scene(name: string, body: untyped) =
  ## A step of the analysis: Nim code and output, Python code and output, checked equal.
  inTabs(pythonCode(pyCells[name]) & "<pre class=\"nb-output\">" &
         xmltree.escape(readFile("expected" / name & ".txt").strip(leading = false)) & "</pre>"):
    nbCode(body)
    checkOutput(name, nb.blk.NbCode.output)

var shown: PlotJson
var figureCount = 0

proc show(pj: PlotJson) = shown = pj

proc plotDiv(data, layout: JsonNode, id: string): string =
  "<div id=\"" & id & "\" class=\"nq-plot\"></div><script>Plotly.newPlot(\"" & id & "\", " &
    $data & ", " & $layout & ", {displaylogo: false, responsive: true, " &
    "modeBarButtonsToRemove: [\"toImage\"]});</script>"

proc sourceDetails(lang, code: string): string =
  let codeHtml = if lang == "nim": "<pre><code class=\"nohighlight nim hljs\">" & highlightNim(code) & "</code></pre>"
                 else: pythonCode(code)
  "<details class=\"nq-plotcode\"><summary>plotting code</summary>" & codeHtml & "</details>"

proc pyFunction(call: string): string =
  ## figs.anomaly_maps(...) -> the source of `def anomaly_maps(`
  let name = call.split("figs.")[1].split("(")[0]
  definition("src/figs.py", "def " & name & "(")

proc nimProc(call: string): string =
  let name = call.split("plots.")[1].split("(")[0]
  definition("plots.nim", "proc " & name & "*(")

template figure(name: string, body: untyped) =
  ## A Plotly figure made twice: with nim-plotly from the Nim frames, and with Python
  ## Plotly from the py-polars ones (recorded by expected.py as JSON).
  inc figureCount
  let py = parseJson(readFile("expected" / name & ".json"))
  let pyCall = pyCells[name]
  inTabs(pythonCode(pyCall) & plotDiv(py["data"], py["layout"], name & "-py") &
         sourceDetails("python", pyFunction(pyCall))):
    nbCode(body)
    let nimCall = nb.blk.NbCode.code
    let nimFig = shown
    let traces = nimFig.traces
    if traces.len != py["data"].len:
      mismatches.add name
      stderr.writeLine "el_nino: " & name & " has " & $traces.len & " traces in Nim, " &
        $py["data"].len & " in Python"
    nbRawHtml: plotDiv(traces, nimFig.layout, name & "-nim") & sourceDetails("nim", nimProc(nimCall))

# Plotly.js once per page, Python highlighting, the tabs' style and script. With
# -d:plotlyJs=<path> the library is inlined (for a page that works offline).
const plotlyJs {.strdefine.} = ""
let plotlyTag =
  if plotlyJs.len > 0: "<script>" & readFile(plotlyJs) & "</script>"
  else: "<script src=\"https://cdn.plot.ly/plotly-4.1.1.min.js\" charset=\"utf-8\"></script>"
nb.doc.context["stylesheet"] = %(nb.doc.context["stylesheet"].getStr & plotlyTag & """
<style>
.nq-tabs { margin: 1.6rem 0; }
.nq-tablist { display: flex; gap: .4rem; }
.nq-tab { font: 600 .95rem/1 var(--mono); letter-spacing: .04em; padding: .55rem 1rem; cursor: pointer;
  border: 1px solid var(--rule); border-bottom: none; border-radius: 6px 6px 0 0;
  background: transparent; color: var(--mute); }
.nq-tab[aria-selected="true"] { background: var(--floe); color: var(--fjord); box-shadow: inset 0 2px 0 var(--fjord); }
.nq-tab:hover { color: var(--fjord); }
.nq-panel > pre:first-child { margin-top: 0; }
.nq-panel > pre:first-child > code { border-top-left-radius: 0; }
pre:has(> code.language-python)::before { content: "python · recorded"; }
.nq-plot { width: 100%; margin: .8rem 0; }
.nq-plotcode summary { cursor: pointer; font: .8rem/1.4 var(--mono); color: var(--mute); margin: .3rem 0; }
</style>
""")

proc tabsScript(): string = """
<script>
window.addEventListener("load", function () {
  // the theme loads highlight.js at the end of the page; add Python to it
  if (!window.hljs) return;
  var s = document.createElement("script");
  s.src = "https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/languages/python.min.js";
  s.onload = function () {
    document.querySelectorAll("code.language-python").forEach(function (el) {
      try { hljs.highlightElement(el); } catch (e) {} });
  };
  document.head.appendChild(s);
});
(function () {
  function choose(lang) {
    document.querySelectorAll(".nq-tabs").forEach(function (t) {
      t.querySelectorAll(".nq-tab").forEach(function (b) {
        b.setAttribute("aria-selected", b.dataset.lang === lang ? "true" : "false"); });
      t.querySelectorAll(".nq-panel").forEach(function (p) {
        p.hidden = p.dataset.lang !== lang;
        if (!p.hidden && window.Plotly) p.querySelectorAll(".nq-plot").forEach(function (d) {
          Plotly.Plots.resize(d); });
      });
    });
    try { localStorage.setItem("nanuq-lang", lang); } catch (e) {}
  }
  document.addEventListener("click", function (e) {
    var b = e.target.closest && e.target.closest(".nq-tab");
    if (b) choose(b.dataset.lang);
  });
  try { var saved = localStorage.getItem("nanuq-lang"); if (saved) choose(saved); } catch (e) {}
})();
</script>
"""

nbText: """
*Every step of this post is shown twice: 👑 in Nim with Nanuq, and 🐍 in Python with
py-polars, in tabs (the choice sticks for the whole page). The Python version came
first, while Nanuq 0.4 was being built, and its outputs are recorded next to its code;
the Nim outputs are the ones this page computed, and the page build checks that they
are the same. The charts and maps are Plotly figures, made with nim-plotly in Nim and
Plotly in Python, from the same data.*

Every few years a patch of the Pacific Ocean, out in the middle of nowhere, warms up by
a degree or two. That sounds like nothing. Yet it floods deserts in Peru, dries out
rainforests in Indonesia, shifts storm tracks over North America, and nudges the
temperature of the whole planet. The warming is called **El Niño**, and right now, in
the autumn of 2026, one of the strongest on record is under way.

This post counts El Niños the way the scientists do, starting from a single column of
monthly sea temperatures, and follows them out into the rest of the world's weather.
Nothing is assumed: if you have never heard of El Niño, this is the place to start.
Along the way it shows off what is new in Nanuq 0.4: rolling windows and exponential
smoothing, cumulative functions, shift and diff, top-k and binning, horizontal
functions, pivot and unpivot, dynamic group-by, as-of joins and a real `Series`.

Data, all public: NOAA's Climate Prediction Center (CPC) for the Niño indices and the
Southern Oscillation Index, NASA GISS (GISTEMP v4) for global temperature, NOAA's
GHCN-Daily for the rain gauge at Piura airport, Peru, and NOAA's ERSSTv5 for the maps.
Downloaded on 1 November 2026.
"""

scene "setup":
  setConfig(tblRows = 12, tblCols = 10, tblWidthChars = 120, floatPrecision = 2)

nbText: """
## 1. A box in the ocean

Along the equator, the trade winds blow from east to west across the Pacific. They push
the sun-warmed surface water towards Indonesia and Australia, where it piles up, and let
cold water well up from the deep along the coast of South America. So the Pacific is
normally warm in the west and cool in the east.

Every two to seven years the trade winds weaken, the warm water sloshes back east, and
the central and eastern Pacific heat up. Fishermen in Peru noticed this centuries ago,
because it came around Christmas and emptied their nets. They called it *El Niño de
Navidad*, the Christmas child.
"""

figure "fig_walker":
  show plots.walkerSchematic()

nbText: """
Here is the same ocean seen from above: the mean sea surface temperature of
1991-2020. The warm pool sits in the west, the cold tongue stretches out from South
America along the equator.
"""

figure "fig_normal":
  show plots.pacificNormal()

nbText: """
To keep watch, scientists average the sea surface temperature over a box on the equator
called **Niño 3.4** (5°N to 5°S, 120°W to 170°W): about 1,100 by 5,500 km, six million
square kilometres of open ocean with no land in it (the black box on the map). CPC
publishes one number per month for that box, back to 1950. Here it is, read into a frame, and its temperature column taken out as a
`Series`, Nanuq 0.4's new one-column type.
"""

scene "s01_box":
  var nino = readCsv("data/nino34.csv").select(col.year, col.month, col.sst)
  echo nino.tail(4)
  let sst = nino["sst"]
  echo &"{sst.len} months, from {sst.min.item(float):.2f} to {sst.max.item(float):.2f} °C"
  echo nino.slice(sst.argMax.item(int), 1)

nbText: """
The warmest month in 76 years of records was September 2026, the latest month in the
file. But a warm month is not yet an El Niño: the ocean has seasons too. The mean for
each calendar month, with `topK` and `bottomK`, shows the box is warmest in spring and
coolest in winter, more than a degree apart.
"""

scene "s01_seasons":
  let climate = nino.groupBy("month").agg(col.sst.mean)
  echo concat([climate.topK(2, by = "sst"), climate.bottomK(2, by = "sst")])

nbText: """
## 2. What is normal?

Climate scientists rarely look at a temperature on its own. They look at the
**anomaly**: how far a month is above or below normal for that time of year. "Normal"
is the average of the same calendar month over a 30-year **base period**, today
1991-2020.

In Nanuq that is one window expression: the mean of `sst` over the base years,
computed separately for each month with `over`.
"""

scene "s02_anomaly":
  let base = col.year.isBetween(1991, 2020)
  nino = nino.withColumns(col.sst.filter(base).mean.over("month").alias("normal"))
             .withColumns((col.sst - col.normal).alias("anomaly"))
  echo nino.filter(col.month == 9 and col.year.isIn([1982, 1997, 2015, 2023, 2026]))

nbText: """
September 2026 was 2.5 °C above a normal September: the ocean is running a fever.

The same idea works for every point of the ocean. Here are three Septembers, each
compared with a normal September: the two biggest El Niños of the satellite era, and
this one.
"""

figure "fig_three_septembers":
  show plots.anomalyMaps(["1997-09", "2015-09", "2026-09"],
                         ["September 1997", "September 2015", "September 2026"])

nbText: """
CPC does one thing differently. It does not use a single base period for all 76 years
but a sliding one, so that each year is compared with the 30 years around it. The file
also carries CPC's own anomaly, and we will see in scene 7 why the difference matters.
"""

nbText: """
## 3. Three months make a season

A single warm month can be a fluke of the weather. So the official **Oceanic Niño
Index (ONI)** is a three-month running mean of the anomaly: the value for "DJF" is the
mean of December, January and February, and so on through the twelve overlapping
seasons of the year.

CPC publishes the ONI as a wide table, one row per year and one column per season,
rounded to one decimal. That shape is good for reading, bad for computing. `unpivot`
turns it into one row per season, and `replaceStrict` maps each season to its middle
month.
"""

scene "s03_table":
  const seasons = ["DJF", "JFM", "FMA", "MAM", "AMJ", "MJJ", "JJA", "JAS", "ASO", "SON", "OND", "NDJ"]
  let oniTable = readCsv("data/oni_table.csv")
  echo oniTable.tail(3)
  var seasonMonth: seq[(string, int)]
  for m, s in seasons: seasonMonth.add (s, m + 1)
  let oni = oniTable.unpivot(index = "year", variableName = "season", valueName = "oni")
    .dropNulls("oni")
    .withColumns(col.season.replaceStrict(seasonMonth).alias("month"))
    .sort(["year", "month"])
  echo oni.tail(3)

nbText: """
Now we rebuild the index ourselves from CPC's monthly anomalies, with a centered
`rollingMean` over three rows, and compare.
"""

scene "s03_rebuild":
  let cpc = readCsv("data/nino34.csv").select(col.year, col.month,
    col("cpc_anomaly").rollingMean(3, center = true).alias("mine"))
  let rebuilt = oni.join(cpc, on = ["year", "month"])
    .withColumns((col.mine - col.oni).abs.alias("diff"))
  echo rebuilt.select(col.diff.len.alias("seasons"), col.diff.max.alias("max_diff"),
                      (col.mine.round(1) != col.oni).sum.alias("off_by_rounding"))

nbText: """
All 920 seasons agree to within 0.05 °C, which is the rounding of the table. Only 14
land on the other side of a rounding tie (CPC averages the unrounded values). We have
rebuilt NOAA's El Niño index in one line.
"""

nbText: """
## 4. Counting El Niños

The rule for an El Niño **event** is simple: the ONI must be at **+0.5 °C or more for
at least five overlapping seasons in a row**. Its cold mirror image, at -0.5 °C or less,
is called **La Niña** (the girl). Anything in between is "neutral". Together they make
the **El Niño-Southern Oscillation**, ENSO for short.

Finding runs is a job for `rleId`: it gives every run of equal values its own number.
Label each season with its phase, number the runs, and keep the runs at least five
seasons long.
"""

scene "s04_events":
  let phase = choose:
    if col.oni >= 0.5: "El Niño"
    elif col.oni <= -0.5: "La Niña"
    else: "neutral"
  let events = oni.withColumns(phase.alias("phase"))
    .withColumns(col.phase.rleId.alias("run"))
    .groupBy("run")
    .agg(col.phase.first,
         format("{} {}", col.season.first, col.year.first).alias("start"),
         format("{} {}", col.season.last, col.year.last).alias("end"),
         col.oni.len.alias("seasons"),
         col.oni.max.alias("peak"), col.oni.min.alias("trough"),
         date(col.year.first, col.month.first, 15).alias("start_date"))
    .filter(col.phase != "neutral" and col.seasons >= 5)
    .drop("run")
  echo events["phase"].valueCounts(sort = true)
  echo events.tail(5).drop("start_date")

nbText: """
25 El Niños and 21 La Niñas since 1950. CPC colours its table red and blue with the
same rule, and our runs match its colouring season by season, all 920 of them. One
detail matters: the rule is applied to the rounded table. On CPC's two-decimal file,
where a +0.46 does not reach +0.5, the same code finds only 22 El Niños.

Look at the last row: the current El Niño began in MAM (March to May) 2026 and is
still going, so it has no end yet. It already counts as an event: JAS is its fifth
season.

The whole record at a glance, red when the index is at +0.5 or more, blue at -0.5 or
less.
"""

figure "fig_oni_bars":
  show plots.oniBars(oni)

nbText: """
## 5. How strong?

Forecasters grade events by their peak: weak from +0.5, moderate from +1.0, strong
from +1.5, very strong from +2.0. `cut` does the binning; `leftClosed` makes each band
include its lower edge. Then `topK` picks the five biggest El Niños.
"""

scene "s05_strength":
  let ninos = events.filter(col.phase == "El Niño").withColumns(
    col.peak.cut([1.0, 1.5, 2.0], labels = ["weak", "moderate", "strong", "very strong"],
                 leftClosed = true).alias("strength"))
  echo ninos["strength"].valueCounts.sort("strength")
  echo ninos.topK(5, by = "peak").select("start", "end", "seasons", "peak", "strength")

nbText: """
The famous ones are all there: 1982-83, 1997-98 and 2015-16 (which by this index
started in late 2014), the three "super El Niños" of the satellite era, and 2023-24,
which just makes the very strong band. The current event is already in third place at
2.2 and, according to CPC's October discussion, still strengthening.

And here is what "very strong" looks like next to its opposite: December 1997, at the
peak of the 1997-98 El Niño, and December 1988, at the peak of a strong La Niña, when
the cold tongue reached far into the central Pacific.
"""

figure "fig_nino_nina":
  show plots.anomalyMaps(["1997-12", "1988-12"], ["El Niño, December 1997", "La Niña, December 1988"])

nbText: """
## 6. 2026, the fast one

How quickly did this one arrive? `diff` gives the change from one season to the next,
and `shift(4)` lets us compare each season with four seasons earlier, about the time it
takes an El Niño to grow.
"""

scene "s06_rise":
  let rise = oni.withColumns(col.oni.diff.alias("step"),
                             (col.oni - col.oni.shift(4)).alias("rise4"))
  echo rise.filter(col.year == 2026).select("season", "oni", "step", "rise4")
  echo rise.topK(5, by = "rise4").select("year", "season", "oni", "rise4")

nbText: """
From MAM to JAS 2026 the index climbed 1.7 °C, the fastest four-season rise since
1950, ahead of 1997. To line events up from their first season, `cumCount` over each
run counts the seasons since onset, and `pivot` puts the big events side by side.
"""

scene "s06_side_by_side":
  let big = [1982, 1997, 2014, 2023, 2026]
  let runs = oni.withColumns(phase.alias("phase"))
    .withColumns(col.phase.rleId.alias("run"))
    .withColumns(col.year.first.over("run").alias("onset"),
                 col.oni.cumCount.over("run").alias("season_no"))
    .filter(col.phase == "El Niño" and col.onset.isIn(big) and col("season_no") <= 8)
  let side = runs.pivot(on = "onset", index = "season_no", values = "oni")
  echo side

nbText: """
Five seasons in, 2026 is ahead of every other event, 1997 included. (The 2014 column
is the 2015-16 event, which began in late 2014 and then idled for months around +0.7
before taking off.)
"""

figure "fig_growth":
  show plots.growth(side)

nbText: """
## 7. A moving ruler

Here is a problem. The whole tropical ocean is getting warmer. If "normal" stays fixed,
a warming ocean looks more and more like El Niño, even when nothing special is going
on. Our fixed 1991-2020 anomaly from scene 2 shows it: `groupByDynamic` with a
ten-year window gives the mean anomaly of each decade.
"""

scene "s07_drift":
  let monthly = readCsv("data/nino34.csv")
    .withColumns(date(col.year, col.month, 1).alias("date"))
    .join(nino.select("year", "month", "anomaly"), on = ["year", "month"])
  echo monthly.filter(col.year >= 1950).groupByDynamic("date", every = "10y").agg(
    col.anomaly.mean.alias("fixed_base"), col("cpc_anomaly").mean.alias("sliding_base"))

nbText: """
Against a fixed base, every decade before 1990 averages 0.2 to 0.5 °C below zero:
the 1950s to 1980s look like a forty-year La Niña. CPC's sliding base keeps every decade
near zero, but it is always computed from past years, so it lags behind a fast
warming. So since February 2026 NOAA uses a new official index, the **Relative ONI
(RONI)**: the Niño 3.4 anomaly minus the average anomaly of the whole tropics (20°N to
20°S), rescaled to the same spread. El Niño is now measured against the rest of the
tropical ocean, not against the past.

Same rules, new ruler: count the events again with RONI and match them to the ONI
events with `joinAsof`, which pairs each ONI event with the RONI event that started
nearest in time, if within six months.
"""

scene "s07_roni":
  let roni = readCsv("data/roni_table.csv")
    .unpivot(index = "year", variableName = "season", valueName = "oni")
    .dropNulls("oni")
    .withColumns(col.season.replaceStrict(seasonMonth).alias("month"))
    .sort(["year", "month"])
  let roniEvents = roni.withColumns(phase.alias("phase"))
    .withColumns(col.phase.rleId.alias("run"))
    .groupBy("run")
    .agg(col.phase.first, col.oni.len.alias("seasons"),
         format("{} {}", col.season.first, col.year.first).alias("roni_start"),
         col.oni.max.alias("roni_peak"),
         date(col.year.first, col.month.first, 15).alias("start_date"))
    .filter(col.phase == "El Niño" and col.seasons >= 5)
    .select("start_date", "roni_start", "roni_peak")
  echo &"ONI: {ninos.height} El Niños, RONI: {roniEvents.height}"
  let paired = ninos.sort("start_date").joinAsof(
    roniEvents.sort("start_date"), on = "start_date", strategy = AsofStrategy.Nearest,
    tolerance = 183.days, coalesce = false)
  echo paired.filter(col("start_date").dt.year >= 2000)
    .select("start", "peak", "roni_start", "roni_peak")
  echo roniEvents.topK(3, by = "roni_peak")
    .sort(["roni_peak", "start_date"], descending = [true, false])

nbText: """
Both rulers count 25 El Niños since 1950, but not quite the same ones, and not equally
strong. Since 2000 the two lists mostly agree, with three exceptions:

- 2023-24 shrinks from 2.0 to 1.4. It peaked while the whole tropical ocean was
  unusually hot, so relative to its surroundings it was a moderate event.
- The weak 2019-20 warm spell is not an El Niño by RONI.
- Neither is the current one, yet. By RONI it reached +0.5 only in AMJ, so JAS was its
  fourth season. NOAA has nevertheless issued an El Niño Advisory: the five-season
  rule is for the history books, while forecasters declare an event as soon as ocean
  and atmosphere agree and are expected to stay that way.

The RONI record holder is 1982-83 at +2.4. That is why CPC's October discussion speaks
of a "historic event" if the 3-month RONI reaches +2.5 or more, which it gives a 54%
chance for September-November and 83% for October-December.

Side by side since 1995, the two rulers mostly agree on the ups and downs. They part
ways where the whole tropics were warm: 2023 and now.
"""

figure "fig_rulers":
  show plots.twoRulers(oni, roni)

nbText: """
## 8. The other half: air pressure

El Niño is not only about water. In the 1920s the British scientist Gilbert Walker,
looking for a way to forecast India's monsoon, found a seesaw in air pressure across
the Pacific: when pressure is high in the east it is low in the west, and vice versa.
He called it the **Southern Oscillation**. Today it is measured as the **Southern
Oscillation Index (SOI)**: the pressure at Tahiti minus the pressure at Darwin,
Australia, standardized. When the trade winds weaken, the SOI drops.

In 1969 the Norwegian meteorologist Jacob Bjerknes showed that Walker's seesaw and the
warm Pacific water were one coupled system: weaker trade winds let the ocean warm, and
a warmer east Pacific weakens the trade winds further. `corr` shows how tightly the
two move together, here on three-month means of both.
"""

scene "s08_soi":
  let soi = readCsv("data/soi.csv").withColumns(col.soi.rollingMean(3, center = true).alias("soi3"))
  let both = soi.join(cpc, on = ["year", "month"]).dropNulls
  echo both.select(col.soi.len.alias("months"), corr("soi3", "mine").alias("r"))
  echo both.filter(col.year == 2026).tail(4)

nbText: """
A correlation of -0.84 over 75 years: when the sea warms, the pressure seesaw tips. In
2026 the SOI swung from positive (La Niña) in the winter to negative in April, and
has stayed there as the ocean warmed.
"""

figure "fig_soi":
  show plots.soiVsOni(both)

nbText: """
## 9. Four boxes and a coastal surprise

Niño 3.4 is not the only box. CPC also tracks Niño 1+2, right off the coast of Peru and
Ecuador, Niño 3 in the east and Niño 4 in the west. The horizontal functions compare
columns within each row: `maxHorizontal` finds the hottest box, `meanHorizontal` the
average of the four.
"""

scene "s09_boxes":
  let anoms = ["nino12_anom", "nino3_anom", "nino34_anom", "nino4_anom"]
  let boxes = readCsv("data/nino_boxes.csv").select(@["year", "month"] & @anoms)
    .withColumns(maxHorizontal(anoms).alias("hottest"), meanHorizontal(anoms).alias("mean"))
  echo boxes.tail(3)
  let coastal = boxes.filter(col("nino12_anom") >= 1.0 and col("nino34_anom").abs < 0.5)
  echo coastal.groupBy("year").agg(col.month.len.alias("months"),
                                   col("nino12_anom").max.alias("coast_max")).sort("year")

nbText: """
In September 2026 the coastal box is 4.7 °C above normal, far ahead of the other
three. The second table hunts for the opposite: months when the coast was at least a
degree too warm while Niño 3.4 stayed neutral. Some are the tail of a big event (the
coast stayed hot in mid-1983 after the centre cooled). Others, like early 2017 and
early 2023, are "coastal El Niños" (*El Niño costero*): no event at all by NOAA's
index, and floods in Peru all the same.

Three of the boxes since 2014 show both stories: in 2017 only the coast warmed; in 2023
and 2026 the coast warmed first and the centre followed.
"""

figure "fig_box_lines":
  show plots.boxLines(boxes)

nbText: """
On the map, March 2017 next to September 2026, with all four boxes drawn.
"""

figure "fig_coastal_maps":
  show plots.anomalyMaps(["2017-03", "2026-09"], ["Coastal El Niño, March 2017", "September 2026"],
                         boxes = ["Niño 4", "Niño 3.4", "Niño 3", "Niño 1+2"])

nbText: """
## 10. Rain in the desert

What does that mean on the ground? Piura, in northern Peru, sits in a coastal desert:
a typical year brings a few tens of millimetres of rain. Its airport's rain gauge has
daily readings in NOAA's GHCN-Daily archive. `groupByDynamic` with a one-year window
sums them per year, and counts the days that were actually reported, because a gauge
that stopped reporting is not a dry year.
"""

scene "s10_piura":
  let rain = readCsv("data/piura_rain.csv", tryParseDates = true).sort("date")
  let years = rain.groupByDynamic("date", every = "1y").agg(
    col("rain_mm").sum.alias("rain_mm"), col("rain_mm").len.alias("days"))
  echo years.select(col("rain_mm").filter(col.days >= 300).median.alias("median, complete years"))
  echo years.topK(4, by = "rain_mm")

figure "fig_piura":
  show plots.piura(years)

nbText: """
In 1983 Piura got about 2,400 mm of rain, in 1998 about 1,700 mm, with two months of
readings missing: more than fifty times a normal year, in a city that has no rain
gutters. (A peer-reviewed tally for the city, Takahashi 2004, gives 2,147 mm for
1982-83 and 1,802 mm for 1997-98: the same picture.) Third is 2017, the coastal El
Niño, with only 79 days on record. A 30-day `rollingSumBy` on the date column finds
the wettest month.
"""

scene "s10_wettest":
  echo rain.withColumns(col("rain_mm").rollingSumBy("date", 30.days).alias("mm_30d"))
    .topK(1, by = "mm_30d")

nbText: """
A thousand millimetres in the thirty days to 1 May 1983, 305 of them on that last day
alone, as the station record has it: more than London gets in a whole typical year, in
one month, in a desert.
"""

nbText: """
## 11. The world's temperature

El Niño does not only move heat around, it lets the ocean give heat back to the air,
and the whole planet warms for a while. To see it we need the global temperature.
NASA's GISTEMP gives the global mean surface temperature anomaly for each month since
1880, against a 1951-1980 base (NASA's choice; the base only shifts the numbers, not
their differences). The file is another wide table, with one column per month and
`***` for months not yet measured.
"""

scene "s11_world":
  const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
  var monthNo: seq[(string, int)]
  for i, m in months: monthNo.add (m, i + 1)
  let gistemp = readCsv("data/gistemp.csv", skipRows = 1, nullValues = ["***"])
  let world = gistemp.select(@["Year"] & @months)
    .unpivot(index = "Year", variableName = "mon", valueName = "temp")
    .withColumns(date(col("Year"), col.mon.replaceStrict(monthNo), 1).alias("date"))
    .dropNulls("temp").sort("date").select("date", "temp")
  let yearly = gistemp.select(col("Year").alias("year"), col("J-D").alias("temp")).dropNulls
  echo yearly.topK(5, by = "temp")

nbText: """
Each new record year breaks the previous best. `cumMax` keeps the running best, so a
record is a year equal to it (and higher than the year before the record).
"""

scene "s11_records":
  let records = yearly.filter(col.temp == col.temp.cumMax and
                              col.temp > col.temp.cumMax.shift(1))
  echo records.filter(col.year >= 1980)["year"].toList(int)

nbText: """
Month-to-month the global temperature is noisy. An exponentially weighted mean,
`ewmMean`, smooths it by giving recent months more weight; with `span = 12` it acts
like a one-year average that reacts faster than a plain 12-month rolling mean.
"""

scene "s11_smooth":
  let smooth = world.withColumns(col.temp.rollingMean(12).alias("rolling12"),
                                 col.temp.ewmMean(span = 12).alias("ewm12"))
  echo smooth.tail(6)

figure "fig_world":
  show plots.world(yearly, smooth, records)

nbText: """
## 12. El Niño's echo

Does the planet warm *after* the Pacific does? Take the global temperature minus its
own ten-year centered mean (to remove the long warming trend), and correlate it with
the Niño 3.4 index shifted by 0 to 6 months.
"""

scene "s12_lag":
  let wiggles = world
    .withColumns(col.date.dt.year.cast(int).alias("year"), col.date.dt.month.cast(int).alias("month"))
    .join(cpc, on = ["year", "month"])
    .withColumns((col.temp - col.temp.rollingMean(121, center = true, minSamples = 61)).alias("wiggle"))
  var lags: seq[Expr]
  for k in 0 .. 6: lags.add corr(col.wiggle, col.mine.shift(k)).alias(&"{k} mo")
  echo wiggles.select(lags)

nbText: """
The match is best when the global temperature lags the Pacific by two to three months.
So a record year should follow an El Niño. `joinAsof` with the default backward
strategy pairs every record year since 1980 with the last El Niño that started before
its middle (1 July), if one started in the two years before.
"""

scene "s12_records":
  let recs = records.filter(col.year >= 1980).withColumns(date(col.year, 7, 1).alias("date"))
  withConfig(tblRows = 20):
    echo recs.joinAsof(ninos.select("start_date", "start", "peak", "strength").sort("start_date"),
                       leftOn = "date", rightOn = "start_date", tolerance = 730.days)
      .drop(["date", "start_date"])

nbText: """
Twelve of the fourteen record years since 1980 came within two years of the start of
an El Niño (1981 is a stretch: the weak 1979-80 event was already over). The other
two, 1990 and 2014, came just before one began. Each of the last three very
strong El Niños gave two record years in a row: 1997-98, 2015-16 and
2023-24. (The very strong 1982-83 event set no record: the eruption of El Chichón in
Mexico in 1982 filled the stratosphere with sun-blocking haze and cooled the planet.)
"""

nbText: """
## 13. Hottest year on record?

Which brings us to now. A pivot of the last four years, one column per year, puts each
month next to the same month of the years before.
"""

scene "s13_pivot":
  let recent = world.filter(col.date.dt.year >= 2023)
    .withColumns(col.date.dt.year.cast(string).alias("year"), col.date.dt.month.alias("mon"))
    .pivot(on = "year", index = "mon", values = "temp")
  echo recent.withColumns(maxHorizontal(all().exclude("mon")).alias("hottest"))

figure "fig_recent":
  show plots.recent(recent)

nbText: """
August 2026 was the warmest August on record and September the second warmest, just
behind 2023, also an El Niño year. Yet January to September 2026 still averages a
little below 2024, because the year started in La Niña.
"""

scene "s13_ytd":
  echo world.filter(col.date.dt.month <= 9)
    .groupBy(col.date.dt.year.alias("year")).agg(col.temp.mean, col.temp.len.alias("months"))
    .topK(3, by = "temp")

nbText: """
If the past is a guide, with a two-to-three-month echo and a peak expected around the
turn of the year, the full heat of this El Niño reaches the global average in the first
half of 2027. Whether 2026 itself beats 2024 depends on the last three months. We will
count again in January.
"""

nbText: """
## What this post used from Nanuq 0.4

- rolling windows: `rollingMean` (centred, with `minSamples`), `rollingSumBy` over a
  date column, and `ewmMean`;
- cumulative functions and runs: `diff`, `shift`, `cumMax`, `cumCount` and `rleId`;
- picking and binning: frame `topK` and `bottomK`, `cut` with labels into an `Enum`,
  `valueCounts`, and `replaceStrict` with a list of pairs;
- horizontal functions: `maxHorizontal` and `meanHorizontal`, plus `corr`;
- reshaping: `unpivot` of NOAA's and NASA's wide tables, and `pivot` for side-by-side
  comparisons and map grids;
- time: `groupByDynamic` by decade and by year, `joinAsof` with `Nearest` and
  `Backward` and a tolerance, and the new `date(year, month, day)` expression;
- a real `Series`: `df["sst"]` with `len`, `min`, `max`, `argMax` and `valueCounts`;
- display: `setConfig(floatPrecision = 2)`.

The Python twin of this post, which recorded the outputs it is checked against, is
[blog/el_nino/el_nino.py](https://github.com/pietroppeter/nanuq/blob/main/docs/blog/el_nino/el_nino.py);
the figures are in [plots.nim](https://github.com/pietroppeter/nanuq/blob/main/docs/blog/el_nino/plots.nim)
and [figs.py](https://github.com/pietroppeter/nanuq/blob/main/docs/blog/el_nino/src/figs.py).

*Sources: NOAA CPC (ONI, RONI, Niño indices, SOI, ENSO Diagnostic Discussion of 8
October 2026, RONI announcement); NASA GISS, GISTEMP v4; NOAA NCEI, GHCN-Daily station
PEM00084401 (Piura) and ERSSTv5; NOAA Ocean Service, "What are El Niño and La Niña?";
K. Takahashi (2004), Annales Geophysicae 22, 3917.*
"""

nbRawHtml: tabsScript()

setCurrentDir(siteDir)
nbSave
if mismatches.len > 0:
  quit "el_nino: outputs differ from py-polars in: " & mismatches.join(", ")
