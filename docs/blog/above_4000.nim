import nimib
import std/[algorithm, math, os, options, sequtils, strutils, strformat, json, tables, xmltree]
import nanuq
import plotly/plotly_types except Color
import ../nanuqtheme
import mountains/plots

nbInit
nb.title = "Above 4000"
# dated slug for the dev log (module names can't start with a digit)
nb.doc.filename = nb.doc.filename.parentDir / "2026-11-01-above-4000.html"
nb.useNanuqTheme(
  titleHtml = "Above <em>4000</em>",
  eyebrow = "Nanuq dev log · November 2026",
  epigraph = "Eighty-two summits, eight treks, and every mountain range on Earth.",
  meta = "Nanuq 0.5 · Polars 0.55 · Nim " & NimVersion & " · rendered with nimib",
  summary = "The Alpine four-thousanders, the great hut-to-hut treks around them and the " &
            "world's 8000-metre peaks, told with the lists, structs, JSON, SQL and Nim " &
            "callbacks new in Nanuq 0.5.",
)

# nimib runs from docs/ (see nimib.toml); the data lives in blog/mountains, and the code
# below reads it with paths relative to that folder.
let siteDir = getCurrentDir()
setCurrentDir("blog" / "mountains")


# ---------------------------------------------------------------------------
# Nim and Python in tabs. The Python side is mountains.py, the same analysis in
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

let pyCells = cells("mountains.py")
var mismatches: seq[string]

proc normalized(s: string): string =
  ## Nim prints a seq as @[...], Python a list as [...]; nothing else is touched.
  s.strip(leading = false).replace("@[", "[")

proc checkOutput(name, got: string) =
  let want = readFile("expected" / name & ".txt")
  if got.normalized != want.normalized:
    mismatches.add name
    stderr.writeLine "above_4000: output of " & name & " differs from py-polars:\n" &
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
      stderr.writeLine "above_4000: " & name & " has " & $traces.len & " traces in Nim, " &
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


scene "setup":
  setConfig(tblRows = 12, tblCols = 10, tblWidthChars = 120, fmtStrLengths = 40, floatPrecision = 1)

nbText: """
*Every step of this post is shown twice: 👑 in Nim with Nanuq, and 🐍 in Python with
py-polars, in tabs (the choice sticks for the whole page). The Python version came
first, while Nanuq 0.5 was being built, and its outputs are recorded next to its code;
the Nim outputs are the ones this page computed, and the page build checks that they
are the same. The charts and maps are Plotly figures, made with nim-plotly in Nim and
Plotly in Python, from the same data.*

## 1. Eighty-two summits

How many mountains in the Alps are higher than 4000 metres? It depends on what you call
a mountain. Mont Blanc has a dozen bumps above 4000 m on its shoulders; is each one a
summit? In 1994 the UIAA, the international federation of mountaineering clubs, settled
it with an official list of **82 four-thousanders**, using a mix of topography (how far
a peak rises above the col that joins it to a higher one) and mountaineering judgement.

Wikipedia has the list as a table. We saved it as a CSV exactly as it comes, footnote
markers and all.
"""

scene "s01_raw":
  let raw = readCsv("data/uiaa_4000ers_raw.csv").filter(col("Nr.").isNotNull)
  echo raw.glimpse(maxItemsPerColumn = 3)

nbText: """
Every column after the height is a string with more than one thing inside. Country is
a list of countries. Isolation (the distance to the nearest higher point) carries the
name of that point. Prominence carries the name of the col. First ascent is a date
followed by a list of people. Let's take them apart one at a time.

## 2. Countries: from a string to a list

The Country column has slashes, spaces and footnotes: `France/ Italy [9]`,
`France Italy`, `Italy/Switzerland`. We strip the footnotes, split on slashes and
spaces, and drop the empty pieces. What comes back is a column of type
`list[str]`.
"""

scene "s02_countries":
  var peaks = raw.select(
    col("Nr.").cast(Int64).alias("nr"),
    col("Summit").str.replaceAll(r"\[.*?\]", "").alias("summit"),
    col("Height (m)").cast(Int64).alias("height"),
    col("Range").alias("range"),
    col("Country")
      .str.replaceAll(r"\[\d+\]", "")
      .str.replaceAll(r"[/ ]+", "/")
      .str.stripChars("/")
      .str.split("/")
      .alias("countries"),
    col("Isolation[6] (km)").alias("isolation"),
    col("Prominence[6] (m)").alias("prominence"),
    col("First ascent[7]").alias("first_ascent"),
  )
  echo peaks.select(col.summit, col.height, col.countries).head(8)

nbText: """
A list column can be measured with `list.len`, searched with `list.contains`, and
turned back into rows with `explode`. Here is how many four-thousanders each country
can claim, how many sit right on a border, and which countries share them (sorting and
joining each list gives one label per combination).
"""

scene "s02_per_country":
  echo peaks.explode("countries")["countries"].valueCounts(sort = true)
  echo peaks.select((col.countries.list.len > 1).sum.alias("on_a_border"))
  echo peaks.groupBy(col.countries.list.sort.list.join(" + ")).agg(len().alias("len")).sort(
    ["len", "countries"], descending = [true, false]
  )

nbText: """
Switzerland has 48, Italy 38, France 26, which adds up to more than 82 because 30
summits sit on a border: 17 between Italy and Switzerland, 13 between France and Italy.
Only 13 are entirely French and 8 entirely Italian, against 31 entirely Swiss, and not
a single one stands on the French-Swiss border. Mont Blanc is on the French-Italian
one, and France and Italy have disagreed about exactly where that border runs over
the top since the 18th century.

## 3. Prominence: from a string to a struct

Prominence is how far a peak rises above the lowest col you must cross to reach
anything higher. It is the number mountaineers use to tell a mountain from a bump on
a ridge. The column packs the number and the name of that col into one string,
`1,043  Col Durand`, and Isolation does the same with a distance and the nearest higher
peak.

`str.extractGroups` pulls both parts out at once into a **struct**: a single column
whose values have named fields, like a small row inside a row. `struct.field` reads
one field back, `unnest` spreads them all into columns.
"""

scene "s03_structs":
  let parts = peaks.select(
    col.summit,
    col.height,
    col.prominence.str.extractGroups(r"^(?<metres>[\d,]+)\s+(?<col>.*)$").alias("prom"),
    col.isolation.str.extractGroups(r"^(?<km>[\d.,]+)\s+(?<higher>.*)$").alias("iso"),
  )
  echo parts.schema["prom"].fields.mapIt(it.name).join(", ")
  echo parts.head(5)

nbText: """
Careful with the commas. Prominence uses them as thousands separators (`2,165`), and
so does isolation, except that isolation also has decimals (`0.6`). A naive cast of
Mont Blanc's isolation, `2,812`, as a decimal comma would put the nearest higher point
2.8 km away; it is Elbrus, in the Caucasus, 2812 km away. We drop the commas before
casting.
"""

scene "s03_prominence":
  peaks = peaks.withColumns(
    col.prominence.str.extract(r"^([\d,]+)").str.replaceAll(",", "").cast(Int64).alias("prom_m"),
    col.prominence.str.extract(r"^[\d,]+\s+(.*)$").str.replaceAll(r"\s*\[.*?\]", "").alias("col"),
    col.isolation.str.extract(r"^([\d.,]+)").str.replaceAll(",", "").cast(Float64).alias("iso_km"),
    col.isolation.str.extract(r"^[\d.,]+\s+(.*)$").alias("higher"),
  )
  echo peaks.select(
    (col.prom_m >= 1000).sum.alias("over_1000"),
    (col.prom_m < 100).sum.alias("under_100"),
    (col.prom_m < 30).sum.alias("under_30"),
  )
  echo peaks.topK(8, by = "prom_m").select(col.summit, col.height, col.prom_m, col("col"), col.iso_km, col.higher)

nbText: """
Only 12 of the 82 are mountains in their own right by the 1000-metre rule. Mont
Blanc's prominence is its whole height above the lowest col on the way to anything
taller, which is somewhere in the flatlands of Russia. Two in five (33) rise less than
100 metres above their col, six of them less than 30: shoulders and towers of bigger mountains,
kept because climbers treat them as separate goals.

## 4. Who climbed them first

The First ascent column is the messiest of all:
`14 July 1865  Croz, Taugwalder, Whymper, Hudson, Douglas and Hadow`. We take the
year with a regular expression, and turn the rest into a list of names by treating
"and" (and the German "mit", which slipped into the English page) as commas.
"""

scene "s04_ascents":
  let ascents = peaks.select(
    col.summit,
    col.height,
    col.first_ascent.str.extract(r"(\d{4})").cast(Int32).alias("year"),
    col.first_ascent
      .str.replace(r"^.*?\d{4}(\[\d+\])?\s*", "")
      .str.replaceAll(r"\[.*?\]|\(.*?\)|"".*?""", "")
      .str.replaceAll(r" (and|mit) ", ", ")
      .str.split(",")
      .list.eval(element().str.stripChars)
      .alias("party"),
  )
  echo ascents.head(6)

nbText: """
Explode the lists and count: who stood first on the most four-thousanders?
"""

scene "s04_who":
  echo ascents.explode("party").dropNulls("party")["party"].valueCounts(sort = true).head(8)

nbText: """
Melchior Anderegg, a mountain guide from the Bernese Oberland, leads with six, ahead
of Christian Almer, another Oberland guide, with five. Most of the famous names of the
period show up with three or four: the British climbers Leslie Stephen, Horace Walker
and Edward Whymper, the Chamonix guides Michel Croz and Michel-Clément Payot. And the
list has its limits: when the page says "Jakob and Melchior Anderegg", our split gives
a lone "Jakob". We fix that in section 9 with a Nim callback.

When did all this happen? Group the years by decade.
"""

scene "s04_decades":
  withConfig(tblRows = 20):
    echo ascents.groupBy((col.year div 10 * 10).alias("decade")).agg(len().alias("len")).sort("decade")
  echo ascents.select(
    col.year.isNotNull.sum.alias("dated"),
    col.year.isBetween(1854, 1865).sum.alias("golden_age"),
    col.year.min.alias("first"),
    col.year.max.alias("last"),
  )

nbText: """
Mountaineers call the years from 1854 (the Wetterhorn) to 1865 (the Matterhorn) the
**golden age of alpinism**. Of the 74 summits with a known year, 36 were first climbed
in those twelve seasons. The very first was the Dôme du Goûter in 1784, two years before
Mont Blanc itself; the last was the Grand Pilier d'Angle, climbed by Walter Bonatti and
Toni Gobbi in 1957.

## 5. On the map

The list has no coordinates, so we join them in from a separate file built from
Wikidata and Camptocamp (see `src/peaks_prep.py`), on the list number.
"""

scene "s05_join":
  let coords = readCsv("data/uiaa_coords.csv")
  peaks = peaks.join(coords, on = ["nr"], how = Left, validate = OneToOne, maintainOrder = MaintainOrderJoin.Left)
  withConfig(floatPrecision = 4):
    echo peaks.select(col.summit, col.height, col.lon, col.lat, col.source).head(5)

figure "fig_peaks":
  show plots.alpsMap(peaks)

nbText: """
All 82 fit in a strip about 250 km long, from the Barre des Écrins in the south-west to
Piz Bernina in the east, and most crowd around two centres: the Mont Blanc massif and
the Valais around Zermatt.

## 6. Eight treks, as JSON

You don't need a rope to see these mountains up close. Several classic multi-day treks
go around them, hut to hut: the Tour du Mont Blanc, the Tour du Cervin around the
Matterhorn, the Tour Monte Rosa, the Tour des Combins, the Walker's Haute Route from
Chamonix to Zermatt, and further south and east the Alta Via 1 of the Aosta Valley and
the Alte Vie 1 and 2 of the Dolomites.

OpenStreetMap volunteers have mapped all of them as *route relations*: a route made of
stages, a stage made of ways (stretches of path), a way made of points. We downloaded
each one from Waymarked Trails, sampled the terrain height at every point, and saved
them as newline-delimited JSON, one trek per line, keeping the nesting
(`src/treks_prep.py`). `readNdjson` reads it into eight rows.
"""

scene "s06_read":
  let treks = readNdjson("data/treks.ndjson", inferSchemaLength = none(int))
  echo treks.shape
  echo treks.schema["stages"].inner.fields.mapIt(it.name).join(", ")
  echo treks.select(col.id, col.name, col.stages.list.len.alias("n_stages"))

nbText: """
Eight rows, but a lot inside them. The `stages` column is a list of structs; each
stage struct holds a list of way structs; each way holds an OpenStreetMap `tags`
struct and a list of points, each point a list of three numbers. How many tag fields?
"""

scene "s06_tags":
  let wayType = treks.schema["stages"].inner.fields[3].dtype.inner
  let tagFields = wayType.fields[3].dtype.fields.mapIt(it.name)
  echo tagFields.len, " ", tagFields.sorted[0 ..< 12].join(", ")

nbText: """
166 of them. Every way carries only the few tags someone bothered to map, and
the struct holds the union of all of them, with nulls everywhere else.

## 7. Unnesting, level by level

Two `explode`s and two `unnest`s turn eight treks into one row per way. On the way we
give the long official names shorter labels.
"""

scene "s07_ways":
  let short = {
    "Tour du Mont Blanc - Itinéraire principal": "Tour du Mont Blanc",
    "Alta via n. 1 delle Dolomiti - Dolomiten-Höhenweg Nr. 1": "Alta Via 1 Dolomites",
    "Alta Via n. 2 delle Dolomiti - Dolomiten-Höhenweg Nr. 2": "Alta Via 2 Dolomites",
    "Alta Via n. 1 della Valle d'Aosta": "Alta Via 1 Aosta",
  }
  let ways = treks.select(col.name.replace(short).alias("trek"), col.stages)
    .explode("stages")
    .unnest("stages")
    .rename({"id": "stage_id", "name": "stage"})
    .explode("ways")
    .unnest("ways")
    .rename({"id": "way_id"})
  echo ways.shape
  echo ways.select(col.trek, col.stage, col.way_id, col.length, col.points).head(4)

nbText: """
Now the tags. OpenStreetMap grades mountain paths on the SAC scale, from Swiss Alpine
Club practice: T1 is a walk, T3 a demanding mountain path, T5 and T6 alpine terrain
where you may need your hands and a head for heights. `struct.field` picks it out of
the big tags struct, and a group-by sums the lengths per grade.
"""

scene "s07_sac":
  let grades = {"hiking": "T1", "mountain_hiking": "T2", "demanding_mountain_hiking": "T3",
                "alpine_hiking": "T4", "demanding_alpine_hiking": "T5", "difficult_alpine_hiking": "T6"}
  let sac = ways
    .withColumns(col.tags.struct.field("sac_scale").replaceStrict(grades, default = "none").alias("sac"))
    .groupBy("trek", "sac")
    .agg((col.length.sum / 1000).alias("km"))
    .pivot(on = "sac", index = "trek", values = "km", sortColumns = true)
    .fillNull(0)
    .sort("trek")
  echo sac

nbText: """
OpenStreetMap stores the grades as words (`mountain_hiking`), which we map back to
the T1-T6 the signposts use; `none` means no grade was mapped (often roads and forest
tracks).
The SAC grades also tell the treks apart: the Dolomite Alte Vie and the Tour du Cervin
have kilometres of T4 and harder, the Tour du Mont Blanc stays mostly on
T1-T2 paths.

## 8. Points: lists, arrays, and a map projection

Each point is `[x, y, elevation]`. The x and y are Web Mercator metres, the projection
of every web map. Since every point has exactly three values, we can cast the inner
list to a fixed-size **array**, and read it with the `arr` namespace.
"""

scene "s08_points":
  const R = 6378137.0  # Web Mercator sphere radius, metres
  var pts = ways.select(col.trek, col.stage, col.way_id, col.points)
    .withRowIndex("way_seq")
    .explode("points")
    .withColumns(col.points.cast(Array(Float64, 3)))
    .select(
      col.trek, col.stage, col.way_seq,
      col.points.arr.get(0).alias("x"),
      col.points.arr.get(1).alias("y"),
      col.points.arr.get(2).alias("ele"),
    )
    .withColumns(
      (col.x / R * 180 / PI).alias("lon"),
      ((col.y / R).sinh.arctan * 180 / PI).alias("lat"),
    )
  echo pts.height
  echo pts.head(4)

nbText: """
A distance in Web Mercator metres is stretched by 1/cos(latitude), about 1.43 at 46°N,
so we shrink each step back. Steps are measured within a way, so gaps between
disconnected ways don't count.
"""

scene "s08_distance":
  pts = pts.withColumns(
    ((col.x.diff ^ 2 + col.y.diff ^ 2).sqrt * (col.lat * PI / 180).cos)
      .over("way_seq").fillNull(0).alias("step")
  ).withColumns((col.step.cumSum.over("trek") / 1000).alias("km"))
  echo pts.groupBy("trek").agg(
    (col.step.sum / 1000).alias("km"),
    col.ele.max.alias("top"),
    col.ele.min.alias("bottom"),
  ).sort("km")

figure "fig_treks":
  show plots.treksMap(pts, peaks)

nbText: """
Two of the eight are far to the east, in the Dolomites, where the limestone towers top
out at 3343 m (the Marmolada) and there are no four-thousanders at all.
"""

figure "fig_dolomites":
  show plots.dolomitesMap(pts)

nbText: """
## 9. How much climbing? It depends on how closely you look

Guidebooks give the Tour du Mont Blanc about 170 km and **10,000 metres of ascent**.
Our 166 km match the first number. For the second, you add up every rise along the
way. But a terrain model has noise, and every little up-and-down gets counted, so the
answer depends on how finely you sample. Average the height over bins of increasing
length and watch the total ascent shrink.
"""

scene "s09_ascent":
  proc ascent(binKm: float): DataFrame =
    pts.groupBy(col.trek, (col.km / binKm).floor.alias("bin"))
      .agg(col.ele.mean)
      .sort(["trek", "bin"])
      .groupBy("trek")
      .agg(col.ele.diff.clip(lowerBound = 0.0).sum.round.alias($int(binKm * 1000) & " m"))

  var table = ascent(0.05)
  for b in [0.1, 0.2, 0.5, 1.0]:
    table = table.join(ascent(b), on = ["trek"])
  echo table.sort("trek")

nbText: """
Bins of 100 metres give the Tour du Mont Blanc 10,183 metres, right on the guidebook
figure; with 1 km bins the passes are smoothed away and only 8,257 m remain. We'll use
100 metres from here on.
"""

figure "fig_profile":
  let passes = newDataFrame:
    km: [8.0, 23.6, 48.0, 64.1, 73.3, 105.5, 152.3]
    label: ["Brévent", "Col de Voza", "Croix du Bonhomme", "Col de la Seigne",
            "Mont Favre", "Grand Col Ferret", "Col de Balme"]
  let tmb = pts.filter(col.trek == "Tour du Mont Blanc").sort("km")
  let labels = passes.joinAsof(tmb.select(col.km, col.ele), on = "km", strategy = AsofStrategy.Nearest)
  show plots.profile(pts, "Tour du Mont Blanc", labels)

nbText: """
## 10. The guidebook's words, decoded

The Aosta Valley's Alta Via 1 is split into 17 official stages, and each stage in
OpenStreetMap carries its itinerary as a list of strings with the altitude written in:
`Sassa (1430 mt.)`. `list.eval` runs an expression on every element of a list, so we
can pull the numbers out of all of them at once and compare them with what the
terrain model says at the start and end of each stage.
"""

scene "s10_stages":
  let av1 = ways.filter(col.trek == "Alta Via 1 Aosta")
    .groupBy("stage_id", maintainOrder = true)
    .agg(col.stage.first, col.itinerary.first)
    .withColumns(
      col.itinerary.list.eval(
        element().str.extract(r"\((\d[\d.]*)\s*mt?\.?\)").str.replaceAll(r"\.", "").cast(Int64)
      ).alias("stop_m"),
      col.stage.str.extract(r"Tappa (\d+)").cast(Int64).alias("stage_no"),
    )
    .sort("stage_no")
  echo av1.select(col.stage_no, col.itinerary, col.stop_m).head(6)

nbText: """
Now the check. For each stage, take the terrain height at its first and last point,
put them in a list too, and compare the two lists element by element.
"""

scene "s10_check":
  let ends = pts.groupBy("stage", maintainOrder = true).agg(
    concatList(col.ele.first, col.ele.last).first.alias("dem_m")
  )
  let check = av1.join(ends, on = ["stage"], maintainOrder = MaintainOrderJoin.Left).withColumns(
    maxHorizontal(@[0, 1].mapIt((col.dem_m.list.get(it) - col.stop_m.list.get(it)).abs))
      .round.cast(Int64).alias("diff_m")
  )
  echo check.filter(col.diff_m > 150).select(col.stage_no, col.itinerary, col.stop_m, col.dem_m, col.diff_m)

nbText: """
Fourteen of the seventeen stages agree with the terrain within 150 metres, about as
close as you can expect from a terrain model and a signpost. Two of the misfits share
one typo: the village of Niel is written `Niel 1(550 mt.)`, a misplaced bracket that
turns 1550 m into a 550-metre valley floor (the terrain says 1567). The third is a hole
in the map: stage 15 should climb to the Rifugio Frassati at 2540 m, but its mapped path
stops 500 metres lower, and stage 16 picks up from the hut.
"""

nbText: """
## 11. Walking time, with a Nim callback

Swiss and German signposts give walking times, not distances, using a rule of thumb
(DIN 33466): 4 km per hour on the flat, 300 metres of ascent per hour, 500 metres of
descent per hour; take the larger of the horizontal and vertical times and add half
the smaller.

That rule fits in an expression, but it reads better as a plain function, and that is
what callbacks are for: `mapElements` hands each value (here a struct with three
fields) to your own function. In Nim, the function is a regular proc on a tuple, and
runs at native speed.
"""

scene "s11_time":
  proc walkingHours(s: tuple[km, up, down: float]): float =
    let horizontal = s.km / 4
    let vertical = s.up / 300 + s.down / 500
    max(horizontal, vertical) + min(horizontal, vertical) / 2

  let legs = pts.groupBy(col.trek, (col.km / 0.1).floor.alias("bin"))
    .agg(col.ele.mean, col.km.max)
    .sort(["trek", "bin"])
    .withColumns(col.ele.diff.over("trek").fillNull(0).alias("d"))
    .groupBy("trek")
    .agg(
      col.km.max.alias("km"),
      col.d.clip(lowerBound = 0.0).sum.alias("up"),
      (-col.d.clip(upperBound = 0.0).sum).alias("down"),
    )
    .withColumns(asStruct("km", "up", "down").mapElements(walkingHours).alias("hours"))
    .withColumns((col.hours / 7).round(1).alias("days_of_7h"))
    .sort("hours")
  echo legs

nbText: """
The rule puts the Tour du Mont Blanc at 75 hours of walking, just under 11 days of
seven hours, which is the classic 11-stage itinerary. The Aosta Valley's Alta Via 1
is the longest of the eight, more than two weeks.

The callback also rescues the first ascents from section 4. When a party is written
as "Jakob and Melchior Anderegg", the two people share one surname, and no regular
expression is going to know which words are first names. A small function can: if an
entry is a single word and the next one has a surname, borrow it.
"""

scene "s11_names":
  proc lendSurnames(party: seq[string]): seq[string] =
    for i, name in party:
      var name = name
      if ' ' notin name and name.len > 0 and name[0].isUpperAscii and
          i + 1 < party.len and ' ' in party[i + 1]:
        name = name & " " & party[i + 1].split(' ')[^1]
      result.add name

  let fixed = ascents.withColumns(col.party.mapElements(lendSurnames).alias("party"))
  echo fixed.explode("party").filter(col.party.str.contains("Anderegg"))["party"].valueCounts(sort = true)

nbText: """
The ranking doesn't move, but the Anderegg family is now complete:

## 12. Asking in SQL

Not everyone thinks in method chains. Nanuq 0.5 can register frames in a SQL context
and query them by name. Which range has the most four-thousanders, and how high and
prominent are they?
"""

scene "s12_sql":
  let ctx = newSQLContext({"peaks": peaks.drop("countries").lazy, "treks": legs.lazy})
  echo ctx.execute("""
      SELECT range, CAST(COUNT(*) AS BIGINT) AS n, MAX(height) AS highest, ROUND(AVG(prom_m)) AS avg_prom
      FROM peaks
      GROUP BY range
      ORDER BY n DESC, highest DESC
  """, eager = true)

nbText: """
## Part 2: The world

## 13. Every mountain range on Earth

Geographers at the University of Bern (the GMBA, Global Mountain Biodiversity
Assessment) have drawn the outline of every named mountain range on Earth, and put
them into a hierarchy: Alps, Western Alps, Pennine Alps, and so on. We use their
selection of about 300 major ranges, saved as NDJSON with the outlines simplified
(`src/gmba_prep.py`). The `Path` column is the hierarchy as one string,
`Europe > Alps`, and `Countries` is another list in disguise.
"""

scene "s13_ranges":
  let ranges = readNdjson("data/gmba_ranges.ndjson").withColumns(
    col.Path.str.split(" > ").alias("path"),
    col.Countries.str.split(", ").alias("countries"),
  )
  echo ranges.select(col.MapName, col.path, col.Elev_High, col.countries).sort("Elev_High", descending = true).head(6)

nbText: """
The heights are a fact check of their own. GMBA computes them from a terrain model
with cells of a few hundred metres, which shaves off the sharpest tops: the Himalaya
reach 8718 m in the inventory, Everest is 8849; the Alps 4713 m, Mont Blanc 4809.

The first element of the path is the continent-sized system the range belongs to.
Which ranges cross the most countries? (GMBA's Alps include the foothills, so they reach
Hungary and Croatia, ten countries in all.)
"""

scene "s13_countries":
  echo ranges.filter(col.Feature != "Ocean").select(
    col.MapName, col.countries.list.len.alias("n"), col.Elev_High.alias("top")
  ).topK(6, by = "n")
  echo ranges.groupBy(col.path.list.first.alias("system")).agg(
    len().alias("n"), col.Elev_High.max.alias("highest")
  ).topK(8, by = "highest")

figure "fig_world":
  show plots.worldMap(ranges)

nbText: """
## 14. Above 8000, according to Wikidata

There are fourteen mountains higher than 8000 metres, all in the Himalaya and the
Karakoram. Ask Wikidata, the free knowledge base behind Wikipedia, for every
"mountain" with an elevation of at least 8000, and you get rather more.
"""

scene "s14_wikidata":
  let wd = readCsv("data/wd_8000.csv").unique("m", keep = First)
  echo wd.height
  echo wd.sort("elev", descending = true).select(col.mLabel, col.elev, col.coord, col.countries).head(6)

nbText: """
Olympus Mons is on Mars (the coordinates start with the Wikidata id of the planet),
and the long tail is mostly American summits whose height was entered in feet. Keep
the Earth, keep metres (nothing on Earth is higher than Everest's 8849), split the
climbers into a list, and look at what is left.
"""

scene "s14_clean":
  let high = wd.filter(
      not col.coord.str.startsWith("<"),
      col.elev <= 8849,
      col.countries.str.contains("Nepal|China|Pakistan|India"),
    )
    .select(
      col.mLabel.alias("peak"),
      col.elev.alias("height"),
      col.prom.alias("prom_m"),
      col.date.str.slice(0, 4).cast(Int32).alias("year"),
      col.climbers.str.split("|").alias("party"),
      col.countries.str.split("|").alias("countries"),
      col.coord.str.extractGroups(r"Point\((?<lon>[-\d.]+) (?<lat>[-\d.]+)\)").alias("where"),
    )
    .unnest("where")
    .withColumns(col("lon", "lat").cast(Float64))
    .sort("height", descending = true)
  echo high.drop(["lon", "lat"])

nbText: """
Fifteen, not fourteen: Lhotse Shar rises only 86 metres above its col with Lhotse, the
kind of bump the UIAA had to rule on in the Alps. Keep the peaks with at least 300 m of
prominence and the classic fourteen are back. Then explode the parties: does anyone
appear twice?
"""

scene "s14_buhl":
  echo high.filter(col.prom_m >= 300).height
  echo high.explode("party").dropNulls("party").groupBy("party").agg(
    col.peak, len().alias("n")
  ).filter(col.n > 1)

nbText: """
Hermann Buhl, the Austrian who reached the top of Nanga Parbat alone in 1953 and was
in the four-man team on Broad Peak in 1957, is the only person with two first ascents
of 8000ers in our data. Here are the fifteen, with the coordinates we pulled out of
Wikidata's `Point(lon lat)` strings:
"""

figure "fig_himalaya":
  show plots.himalayaMap(high)

nbText: """
## 15. Two golden ages

The fourteen were first climbed between Annapurna in 1950 and Shishapangma in 1964,
a golden age of Himalayan climbing that looks a lot like the Alpine one a century
earlier. Stack the two tables (`vstack` needs the same columns) and compare.
"""

scene "s15_golden":
  let alps = fixed.select(col.year, lit("Alps 4000").alias("region"))
  let himalaya = high.filter(col.prom_m >= 300).select(col.year, lit("8000ers").alias("region"))
  let both = alps.vstack(himalaya).dropNulls
  echo both.groupBy("region").agg(
    len().alias("n"),
    col.year.min.alias("first"),
    col.year.median.alias("median"),
    col.year.max.alias("last"),
    (col.year.quantile(0.75) - col.year.quantile(0.25)).alias("years_for_middle_half"),
  ).sort("region")

nbText: """
The middle half of the Alpine first ascents took 22 years; for the Himalayan giants it
took 3.

## 16. Saving it, as JSON

Nested data goes back to JSON as easily as it came in: one line per trek, with the
stage list intact.
"""

scene "s16_write":
  let summary = legs.withColumns(col("km", "up", "down", "hours").round(1)).join(
    ways.groupBy("trek").agg(col.stage.unique(maintainOrder = true).alias("stages")), on = ["trek"], how = Left, maintainOrder = MaintainOrderJoin.Left
  )
  let path = getTempDir() / "treks_summary.ndjson"
  summary.writeNdjson(path)
  let line = readFile(path).splitLines[0]
  echo line[0 ..< min(200, line.len)]

nbText: """
## What this post used from Nanuq 0.5

- nested data types: `List`, `Array` and `Struct` columns, read from CSV strings, NDJSON
  and Parquet, inspected through `schema` (`inner`, `fields`);
- the `list` namespace: `len`, `get`, `first`, `sort`, `join`, `eval(element() ...)`, plus `explode`,
  `concatList` and `vstack`;
- strings into lists and structs: `str.split`, `str.extractGroups`;
- the `struct` namespace and `asStruct`, `unnest`, the `arr` namespace for fixed-size
  arrays;
- JSON: `readNdjson` with full schema inference, and `writeNdjson`;
- SQL: `newSQLContext` and `execute`;
- Nim callbacks: `mapElements` with a proc on a typed tuple, and on a `seq[string]`.

The Python twin of this post, which recorded the outputs it is checked against, is
[blog/mountains/mountains.py](https://github.com/pietroppeter/nanuq/blob/main/docs/blog/mountains/mountains.py);
the figures are in [plots.nim](https://github.com/pietroppeter/nanuq/blob/main/docs/blog/mountains/plots.nim)
and [figs.py](https://github.com/pietroppeter/nanuq/blob/main/docs/blog/mountains/src/figs.py);
the data preparation scripts are in [src/](https://github.com/pietroppeter/nanuq/tree/main/docs/blog/mountains/src).

*Sources: the UIAA list of Alpine four-thousanders as published on English Wikipedia;
Wikidata; Camptocamp; OpenStreetMap contributors (ODbL), through Waymarked Trails;
the AWS Terrain Tiles (Mapzen/Tilezen terrain); the GMBA Mountain Inventory v2
(Snethlage et al. 2022, earthenv.org). Downloaded on 1 November 2026.*
"""

nbRawHtml: tabsScript()

setCurrentDir(siteDir)
nbSave
if mismatches.len > 0:
  quit "above_4000: outputs differ from py-polars in: " & mismatches.join(", ")
