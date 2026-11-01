import nimib
import std/[json, os, sequtils, strutils, tables, xmltree]
import db_connector/db_sqlite
import nanuq
import nanuq/[database, testing]
import plotly/plotly_types except Color
import ../nanuqtheme
import go/[goboard, plots]

nbInit
nb.title = "Move 37"
# dated slug for the dev log (module names can't start with a digit)
nb.doc.filename = nb.doc.filename.parentDir / "2026-11-01-move-37.html"
nb.useNanuqTheme(
  titleHtml = "Move <em>37</em>",
  eyebrow = "Nanuq dev log · November 2026",
  epigraph = "Four hundred years of go games, and the move that changed them.",
  meta = "Nanuq 0.6 · Polars 0.55 · Nim " & NimVersion & " · rendered with nimib",
  summary = "Ninety-eight thousand professional games, 2.8 million amateur ones and the " &
            "champions of Italian go, told with the streaming, sinks, Decimal, Binary, " &
            "bitwise, serialization, database and Excel features new in Nanuq 0.6.",
)

# nimib runs from docs/ (see nimib.toml); the data lives in blog/go, and the code
# below reads it with paths relative to that folder.
let siteDir = getCurrentDir()
setCurrentDir("blog" / "go")

# ---------------------------------------------------------------------------
# Nim and Python in tabs. The Python side is go.py, the same analysis in
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

let pyCells = cells("go.py")
var mismatches: seq[string]

proc normalized(s: string): string =
  ## Nim prints a seq as @[...], Python a list as [...]; and in a glimpse Python shows
  ## a Binary value as b'...', Rust as the bare bytes. Nothing else is touched.
  var lines: seq[string]
  for line in s.strip(leading = false).replace("@[", "[").splitLines:
    lines.add(if line.startsWith("$ ") and "<binary>" in line:
                line.replace(" b'", " ").replace("', ", ", ").strip(leading = false, chars = {'\''})
              else: line)
  lines.join("\n")

proc checkOutput(name, got: string) =
  let want = readFile("expected" / name & ".txt")
  if got.normalized != want.normalized:
    mismatches.add name
    stderr.writeLine "move_37: output of " & name & " differs from py-polars:\n" &
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
      stderr.writeLine "move_37: " & name & " has " & $traces.len & " traces in Nim, " &
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
  setConfig(tblRows = 12, tblCols = 10, tblWidthChars = 120, fmtStrLengths = 40, floatPrecision = 3)

nbText: """
*Every step of this post is shown twice: 👑 in Nim with Nanuq, and 🐍 in Python with
py-polars, in tabs (the choice sticks for the whole page). The Python version came
first, while Nanuq 0.6 was being built, and its outputs are recorded next to its code;
the Nim outputs are the ones this page computed, and the page build checks that they
are the same. The boards and charts are Plotly figures, made with nim-plotly in Nim and
Plotly in Python, from the same data.*
"""

nbText: """
## Part 1: Ninety-eight thousand professional games

## 1. The board, the stones, the rules

Go is played on a grid of 19 by 19 lines. Black and White take turns placing one stone
on an empty intersection; stones never move after that. Stones of the same colour that
touch along the lines form a group, and a group whose last empty neighbouring point
(its last *liberty*) is filled by the opponent is captured and taken off the board. At
the end, each player counts the area they surround. Black moves first, which is an
advantage, so White gets a few points of compensation, called *komi*.

Games are written down in SGF, a plain-text format where a move is two letters, the
column and the row, from `a` (left, top) to `s` (right, bottom). `pd` is the fourth
point from the right and the fourth from the top. Our database packs the moves of each
game into one **Binary** value, two bytes per move. Binary columns are new in 0.6.

What is in it: the SGF letters themselves, one byte each, so `pd` is the two bytes 112
and 100. A String column would have worked just as well; we use Binary to try out the
new type. It does fit the job: move *n* always sits at bytes 2*n* and 2*n*+1, `bin.get`
hands back a byte as a number (`a` is 97, so a column is the byte minus 97), and
looking for an opening is a prefix match on bytes.
"""

scene "s01_read":
  let pro = readParquet("data/pro_games.parquet")
  echo pro.select("file", "DT", "PB", "PW", "KM", "RE", "moves").glimpse(maxItemsPerColumn = 2)

nbText: """
To draw a game we turn the bytes into points. `bin.size` tells how many bytes there
are; the bytes come out one by one with `bin.get`. Here are the first 37 moves of the
second game between AlphaGo (Black) and Lee Sedol (White).
"""

scene "s01_points":
  let game2 = pro.filter(col("file") == "AlphaGo/LeeSedol/2.sgf")
  let first37 = game2
    .select(intRange(0, 37).alias("move"), col.moves.first)
    .select(
      (col.move + 1).alias("move"),
      `when`(col.move mod 2 == 0).then("B").otherwise("W").alias("color"),
      (col.moves.bin.get(col.move * 2).cast(Int64) - 97).alias("x"),
      (col.moves.bin.get(col.move * 2 + 1).cast(Int64) - 97).alias("y"),
    )
  echo first37.tail(4)

figure "fig_move37":
  show plots.board(first37, "AlphaGo vs Lee Sedol, game 2, moves 1 to 37", labels = first37.select(
    col.x, col.y, col.move.cast(String).alias("text"),
    `when`(col.color == "B").then("white").otherwise("black").alias("fg")))

nbText: """
Move 37 is the black stone at P10, alone in the middle of the right side. Moves near the
edge, on the third line, take territory; moves on the fourth line build influence
towards the centre. A stone on the fifth line, this early, gives White an easy third
line underneath. Michael Redmond, commentating in English, called it "a very surprising
move". Fan Hui, who had lost to AlphaGo five months earlier: "It's not a human move.
I've never seen a human play this move."

## 2. Komi, exactly

How many points should White get for moving second? Go has argued about it for a
century. Old Japanese games have no komi at all; komi appeared in the 1930s, and
professionals went from 4.5 to 5.5, 6.5 and in China 7.5 points. The half point is there
so that a game cannot end in a tie.

Half points are exactly the kind of number that floating point gets almost right.
**Decimal** columns, new in 0.6, store them exactly: `str.to_decimal(scale=1)` reads
the `KM` property as a number with one digit after the point.
"""

scene "s02_komi":
  let games = pro
    .filter(col("SZ").isNull or col("SZ") == "19", col("HA").isNull)
    .withColumns(
      col("DT").str.extract(r"^(\d{4})").cast(Int64).alias("year"),
      col("KM").str.stripChars.str.toDecimal(scale = 1).alias("komi"),
      col("RE").str.extract(r"^([BW])\+").alias("winner"),
      col("RE").str.extract(r"^[BW]\+(\d+(?:\.\d)?)$").str.toDecimal(scale = 1).alias("margin"),
    )
  echo games.groupBy((col.year div 10 * 10).alias("decade")).agg(
    len().alias("games"), col.komi.mode.first.alias("usual_komi")
  ).filter(col.decade >= 1920).sort("decade")

nbText: """
Did it work? With komi 0, Black won 58% of the decisive games. Each extra point of
komi took away about two and a half points of percentage, and at 6.5 the game is a
coin toss: 50.2%.
"""

scene "s02_fair":
  let fair = games
    .filter(col.winner.isNotNull)
    .groupBy("komi")
    .agg(len().alias("games"), (col.winner == "B").mean.alias("black_wins"))
    .filter(col.games >= 300, col.komi.isNotNull)
    .sort("komi")
  echo fair

figure "fig_komi":
  show plots.bars(fair.withColumns(col.komi.cast(String).alias("label")), "label", "black_wins",
                  "How often Black wins, by komi (professional games, no handicap)", "Black wins",
                  yformat = ".0%")

nbText: """
A whole-number komi such as 5 can end in a draw, called *jigo*. Decimals make the
test exact: a komi is whole when `komi == komi.floor()`, and the margins of half-point komi
games always end in `.5`.
"""

scene "s02_jigo":
  echo games.filter(col.komi.isNotNull).groupBy((col.komi == col.komi.floor).alias("whole_komi")).agg(
    len().alias("games"),
    (col("RE") == "Jigo").sum.alias("draws"),
    (col.margin == lit("0.5").str.toDecimal(scale = 1)).sum.alias("half_point_wins"),
  ).sort("whole_komi")

nbText: """
## 3. Where the first stone goes

The board has eight symmetries (four rotations, each with a mirror image), so the
opening move at `pd` and the one at `dp` are the same move. We fold every first move
into one corner by counting lines from the nearest edge: a stone on the third line from
one edge and the fourth from the other is a *3-4 point*, the classic *komoku*; the
*4-4 point* is *hoshi*, a star point.
"""

scene "s03_first":
  proc lineFromEdge(byte: int): Expr =
    let v = col.moves.bin.get(byte).cast(Int64) - 97 + 1
    minHorizontal(v, 20 - v)

  let first = games
    .filter(col.moves.bin.size >= 2, col.year.isNotNull)
    .withColumns(lineFromEdge(0).alias("a"), lineFromEdge(1).alias("b"))
    .withColumns(
      format("{}-{}", minHorizontal(col.a, col.b), maxHorizontal(col.a, col.b)).alias("point"),
      `when`(col.year <= 1867).then("1: Edo, to 1867")
        .`when`(col.year <= 1945).then("2: 1868-1945")
        .`when`(col.year <= 1990).then("3: 1946-1990")
        .`when`(col.year <= 2016).then("4: 1991-2016")
        .otherwise("5: AI era, 2017-").alias("era"),
    )
  echo first.groupBy("era", "point").agg(len().alias("len")).withColumns(
    (col.len / col.len.sum.over("era")).alias("share")
  ).filter(col.share > 0.02).sort(["era", "share"], descending = [false, true])

nbText: """
In the Edo period nearly nine games in ten opened on a 3-4 point. The 4-4 point took
over in the twentieth century, with the "New Opening" of Go Seigen and Kitani Minoru in
the 1930s and, later, with komi: a fast, open style pays when Black has points to give
back.
"""

figure "fig_first":
  let freq = first
    .withColumns(
      (col.moves.bin.get(0).cast(Int64) - 97).alias("x"),
      (col.moves.bin.get(1).cast(Int64) - 97).alias("y"),
      col.era.str.slice(3).alias("panel"),
    )
    .groupBy("panel", "x", "y").agg(len().alias("len"))
    .withColumns((col.len / col.len.sum.over("panel")).alias("share"))
  show plots.heatBoards(freq, ["Edo, to 1867", "1868-1945", "1946-1990", "1991-2016", "AI era, 2017-"],
                        "Where Black puts the first stone")

nbText: """
The heatmaps also show a habit: Black's first stone goes in the top-right corner, from
Black's point of view. It is a courtesy, leaving the corner nearest to the opponent's
right hand free.

## 4. Searching the moves

A Binary column can be searched without decoding it. `bin.starts_with` finds games by
their first moves, `bin.slice` cuts out a few bytes, and `bin.encode` shows bytes as
hexadecimal text (`70 64` is `p d`). Before AlphaGo, the most common start was Black
at `pd` and White at `dd`, the two top corners; since 2017 it is `pd` and `dp`.
"""

scene "s04_search":
  echo games.filter(col.moves.bin.size >= 4, col.year.isNotNull).groupBy(
    (col.year >= 2017).alias("after_alphago")
  ).agg(
    len().alias("games"),
    col.moves.bin.startsWith("pd").mean.alias("start_pd"),
    col.moves.bin.startsWith("pddp").mean.alias("start_pddp"),
    col.moves.bin.slice(0, 4).mode.first.alias("common_start"),
    col.moves.bin.slice(0, 4).bin.encode(Hex).mode.first.alias("as_hex"),
  ).sort("after_alphago")

nbText: """
## 5. The 3-3 invasion

The clearest trace AlphaGo left on human play is in the corners. When one side holds a
4-4 point, the other can slide in underneath at the 3-3 point and live in the corner.
Textbooks said this was fine *late* in the game, but giving the opponent a wall this
early was bad style. AlphaGo did it at once, and won. Within a year everybody did.

We write the test as one expression: a game has an early 3-3 invasion if, in its first
twelve moves, some corner has both its 4-4 point and the 3-3 point beneath it. Moves come
out of the Binary column as a list of two-letter strings.
"""

scene "s05_invasion":
  let moves12 = col.moves.bin.slice(0, 24).cast(String).str.extractAll("..")
  let early33 = anyHorizontal(
    [("dd", "cc"), ("pd", "qc"), ("dp", "cq"), ("pp", "qq")].mapIt(
      moves12.list.contains(it[0]) and moves12.list.contains(it[1]))
  ).alias("early_33")
  let invasions = games
    .filter(col.year >= 1990)
    .groupBy("year")
    .agg(len().alias("games"), early33.mean)
    .sort("year")
  echo invasions.tail(13)

nbText: """
Between 1990 and 2017, a bit more than a game in five had an early 3-3 point next to a
star point (some were the old, slow kind of invasion, or a 3-3 point played first). In
2018, a year after AlphaGo's 60 online wins against top professionals, it jumped to
almost a game in two, and it stayed there.
"""

figure "fig_invasion":
  show plots.lines(invasions, "year", [("early_33", "early 3-3 invasions", "#b4462b")],
                   "Professional games with a 3-3 invasion in the first 12 moves", "share of games",
                   events = [(2016.2, "AlphaGo-Lee Sedol"), (2017.0, "AlphaGo Master online")], yformat = ".0%")

nbText: """
We will want the same yardstick for amateurs in Part 2. Expressions can now be
**serialized**: `meta.serialize` turns one into JSON (or a compact binary form), and
`pl.Expr.deserialize` brings it back, in another script or another language. We save
`early_33` to a file.
"""

scene "s05_save":
  writeFile("early_33.json", early33.meta.serialize(Json))
  echo Expr.deserialize(readFile("early_33.json"), Json).meta.outputName

nbText: """
## 6. Same position, different order

Players reach the same opening position along different move orders. To find them,
go programs give every position a *Zobrist hash*: draw one random 64-bit number for each
point and colour, and XOR together the numbers of the stones on the board. XOR is
commutative, so the order of moves doesn't matter, and two different positions almost
never get the same hash. (A capture would XOR a stone away again; there are none this
early.)

**Bitwise** operations are new in 0.6. `bitwise_xor` is an aggregation, so the hash of
each game's first ten moves is a `group_by`.
"""

scene "s06_zobrist":
  let keys = readCsv("data/zobrist.csv", schemaOverrides = {"point": Int64, "key": UInt64})
  let openings = games
    .filter(col.moves.bin.size >= 20, col.year >= 1990)
    .select(col.file, col.year, col.moves.bin.slice(0, 20).cast(String).str.extractAll("..").alias("mv"))
    .withColumns(lit(@["B", "W", "B", "W", "B", "W", "B", "W", "B", "W"]).alias("color"))
    .explode("mv", "color")
    .withColumns(((col.mv.str.slice(1, 1).str.toInteger(base = 36) - 10) * 19 +
                  col.mv.str.slice(0, 1).str.toInteger(base = 36) - 10).alias("point"))
    .join(keys, on = ["point", "color"], maintainOrder = MaintainOrderJoin.Left)
    .groupBy("file", "year")
    .agg(col.key.bitwiseXor.alias("zobrist"), col.mv.str.join("").alias("order"))
  echo openings.sort("file").head(3)

nbText: """
Grouping by the hash shows the most played positions after ten moves since 1990, and
how many different move orders led to each.
"""

scene "s06_top":
  let top = openings
    .groupBy("zobrist")
    .agg(len().alias("games"), col.order.nUnique.alias("orders"), col.order.mode.first.alias("example"),
         col.year.min.alias("first_year"), col.year.max.alias("last_year"))
    .sort("games", descending = true)
    .head(5)
  echo top.withColumns(col.zobrist.cast(String).alias("hash")).drop("zobrist")

nbText: """
Good keys are random bits. `bitwise_count_ones` counts the bits set to 1 (we expect
about half of 64), `bitwise_leading_zeros` counts the zero bits at the front, and the
aggregations `bitwise_and` and `bitwise_or` keep the bits that are set in all keys, or in
any key.
"""

scene "s06_bits":
  echo keys.select(
    col.key.bitwiseCountOnes.mean.alias("mean_ones"),
    col.key.bitwiseCountOnes.min.alias("min_ones"),
    col.key.bitwiseCountOnes.max.alias("max_ones"),
    col.key.bitwiseLeadingZeros.max.alias("leading_zeros_max"),
    col.key.bitwiseAnd.alias("all_and"),
    col.key.bitwiseOr.bitwiseCountOnes.alias("all_or_ones"),
  )

nbText: """
## Part 2: Two point eight million amateur games

## 7. A file too big to read

The Online Go Server (OGS) has been running since 2005. Its complete public record, 56
million games up to May 2025, comes as a single 46 GB gzipped file with one JSON object
per line: 200 GB once unpacked, far more than the memory of a laptop. We streamed it
once over the network and kept every twentieth line: **2,820,649 games** in a 10.3 GB
NDJSON file. That is still too big to read comfortably, which is the point.

The post ships the first 2,000 lines of that file, so every cell below runs. Each line
is the raw API record of one game: players with their ranks, board size, komi, rules,
clock settings, the outcome and the moves.

Let Polars guess the types, and it gives up: the same field holds a boolean on one line
and a number on another.
"""

scene "s07_guess":
  try:
    discard readNdjson("data/ogs_slice.ndjson")
  except PolarsError as e:
    echo "read failed: ", e.msg.split("'")[0].strip, " ..."

nbText: """
So we say what we want, as a schema, and leave the rest out. The other fields, more
than a hundred, are never even parsed. `ignore_errors` turns the few values that don't
fit into nulls.
"""

scene "s07_schema":
  let player = Struct({"username": String, "rank": Float64, "professional": Boolean})
  let schema = {
    "game_id": Int64, "start_time": Int64, "width": Int64, "height": Int64,
    "handicap": Int64, "komi": Float64, "rules": String, "outcome": String,
    "winner": Int64, "black_player_id": Int64,
    "players": Struct({"black": player, "white": player}),
    "time_control": Struct({"speed": String}),
    "moves": List(List(Int64)),
  }
  let raw = scanNdjson("data/ogs_slice.ndjson", schema = schema, ignoreErrors = true)
  echo raw.head(3).collect

nbText: """
## 8. Streaming into Parquet

Now the query: one row per game, with the start as a datetime, the board size, komi as
a Decimal, the two ranks, the result, the number of moves, and the first twelve moves
turned into the same two-letter Binary form as the professional games. OGS gives a
move as `[x, y, milliseconds]`, and `[-1, -1, ...]` for a pass.

OGS ranks are numbers: 30 is 1 dan, 29 is 1 kyu, 20 is 10 kyu. Kyu grades go down as
players get stronger, from 30 kyu (a beginner) to 1 kyu; then dan grades go up, from 1
to about 9 dan for amateurs.
"""

scene "s08_query":
  const letters = "abcdefghijklmnopqrstuvwxyz"
  proc sgfLetter(i: Expr): Expr =
    `when`(i >= 0).then(lit(letters).str.slice(i, 1)).otherwise("t")

  let ogs = raw.filter(col.width == col.height).select(
    col.game_id,
    fromEpoch("start_time", EpochUnit.Seconds).alias("started"),
    col.width.alias("size"),
    col.handicap,
    col.komi.cast(Decimal(10, 1)),
    col.rules.str.toLowercase,
    col.time_control.struct.field("speed").alias("speed"),
    col.players.struct.field("black").struct.field("rank").alias("black_rank"),
    col.players.struct.field("white").struct.field("rank").alias("white_rank"),
    col.outcome,
    `when`(col.winner == col.black_player_id).then("B")
      .`when`(col.winner.isNotNull).then("W").alias("winner"),
    col.moves.list.len.alias("n_moves"),
    col.moves.list.head(12).list.eval(
      sgfLetter(element().list.get(0)) + sgfLetter(element().list.get(1))
    ).list.join("").cast(Binary).alias("moves"),
  )
  echo ogs.head(0).collect

nbText: """
Nothing has run yet: `ogs` is a lazy query, and collecting zero rows of it only shows
its columns. The new **streaming engine** runs it in
batches, so memory stays flat however big the file is, and `sink_parquet` writes the
result straight to disk without ever building the whole table. On the 10.3 GB file
(on a 4-core machine with 15 GB of memory) the streaming run took 75 seconds and 0.13 GB
of working memory. The same query collected in memory took 89 seconds and 11.8 GB.
Here it is on the slice.
"""

scene "s08_sink":
  ogs.sinkParquet("ogs_slice.parquet")
  echo scanParquet("ogs_slice.parquet").select(
    len().alias("games"), col.started.min.alias("first"), col.started.max.alias("last")
  ).collect

nbText: """
Is the streamed result the same as an ordinary in-memory run? The new **testing
helpers** answer with one line: `assert_frame_equal` raises an error that points at the
first difference, and returns quietly when there is none.
"""

scene "s08_check":
  assertFrameEqual(readParquet("ogs_slice.parquet"), ogs.collect(Engine.InMemory))
  echo "streaming and in-memory results agree"

nbText: """
## 9. Growth, AlphaGo and the lockdowns

The streamed table of all 2.8 million games is 80 MB of Parquet. To keep the post
small we ship every fifth game of it: 563,622 games, a 1% sample of everything played on
OGS. Two moments stand out in the number of games started each month: March 2016, the week AlphaGo beat
Lee Sedol, and spring 2020, when half the world was told to stay home.
"""

scene "s09_months":
  let gamesOgs = readParquet("data/ogs_games.parquet")
  let monthly = gamesOgs.groupBy(col.started.dt.truncate("1mo").dt.date.alias("month")).agg(len().alias("len")).sort("month")
  echo monthly.filter(col.month.isBetween(date(2016, 1, 1), date(2016, 6, 1)) or
                      col.month.isBetween(date(2020, 1, 1), date(2020, 6, 1)))

nbText: """
March 2016 had twice the games of February. The lockdowns of 2020 did more, and for
longer: from March the number of games grew by half and stayed high all year.
"""

figure "fig_months":
  show plots.lines(monthly.withColumns((col.len * 100).alias("games")), "month",
                   [("games", "games per month (estimated: 1% sample × 100)", "#8c5a2b")],
                   "Games started on OGS each month", "games",
                   events = [("2016-03-09", "AlphaGo-Lee Sedol"), ("2020-03-15", "lockdowns")], mode = "lines")

nbText: """
## 10. Small boards, fast games

Online, half the games are on smaller boards: 9×9 games last ten minutes and teach the
tactics, 13×13 is a step towards the full board. Most games are played live, the rest by
correspondence, a move a day.
"""

scene "s10_sizes":
  echo gamesOgs.filter(col.size.isIn([9, 13, 19])).groupBy("size").agg(
    len().alias("games"),
    (len() / gamesOgs.height).alias("share"),
    col.n_moves.median.alias("median_moves"),
    col.speed.isIn(["blitz", "live"]).mean.alias("blitz_or_live"),
  ).sort("size")

nbText: """
## 11. Does the stronger player win?

Ranks are supposed to predict results. We take even games (no handicap) on the full
board that ended with a winner, and group them by the rank difference between the two
players, rounded to whole grades.
"""

scene "s11_gap":
  let even = gamesOgs.filter(
    col.size == 19, col.handicap == 0, col.winner.isNotNull, col.n_moves >= 20
  ).withColumns((col.black_rank - col.white_rank).round.cast(Int64).alias("gap"))
  let stronger = even
    .filter(col.gap != 0)
    .groupBy(col.gap.abs.alias("grades"))
    .agg(len().alias("games"),
         ((col.gap > 0) == (col.winner == "B")).mean.alias("stronger_wins"))
    .filter(col.grades <= 9)
    .sort("grades")
  echo stronger

nbText: """
One grade of difference gives the stronger player 58% of the games, four grades three
games in four, and it levels off around 80%. Ranks on a server drift, players have off
days, and the handicap system exists for a reason: in a handicap game, the weaker
player starts with extra stones, one for each grade of difference.
"""

figure "fig_gap":
  show plots.lines(stronger, "grades", [("stronger_wins", "stronger player wins", "#2b6c8f")],
                   "Even games on 19×19: how often the higher-ranked player wins", "share of games",
                   yformat = ".0%")

nbText: """
## 12. Do amateurs play like AlphaGo?

Back to the saved expression from section 5. We load `early_33` from its JSON file and
run it on the amateur games: the same yardstick, not a copy of the code. Strong
amateurs (dan grades, rank 30 and up) and weaker ones (kyu grades), year by year, for
years with at least 50 such games.
"""

scene "s12_amateurs":
  let early33Saved = Expr.deserialize(readFile("early_33.json"), Json)
  let amateurs = gamesOgs
    .filter(col.size == 19, col.handicap == 0, col.n_moves >= 30)
    .withColumns(col.started.dt.year.alias("year"),
                 `when`(minHorizontal(col.black_rank, col.white_rank) >= 30)
                   .then("dan").otherwise("kyu").alias("level"))
    .groupBy("year", "level")
    .agg(len().alias("games"), early33Saved.mean)
    .filter(col.games >= 50)
    .sort(["year", "level"])
  let sideBySide = amateurs.pivot(on = "level", index = "year", values = "early_33").join(
    invasions.select(col.year, col.early_33.alias("pro")), on = ["year"], how = Left, maintainOrder = MaintainOrderJoin.Left).filter(col.year >= 2014)
  echo sideBySide

nbText: """
Strong amateurs followed the professionals: under a third of their games before 2018,
one in two from 2019. (2018 is missing because the sample has too few games between two
dan players that year.) Kyu players had been playing early 3-3 points more than the
professionals all along (it is the simple, safe way to take a corner) and drifted up
slowly.
"""

figure "fig_amateurs":
  show plots.lines(sideBySide.filter(col.year <= 2024), "year",
                   [("pro", "professionals", "#b4462b"), ("dan", "OGS, dan players", "#2b6c8f"),
                    ("kyu", "OGS, kyu players", "#8fb3c9")],
                   "Early 3-3 invasions: professionals and amateurs", "share of games",
                   events = [(2016.2, "AlphaGo")], yformat = ".0%")

nbText: """
## Part 3: A go engine in a callback

## 13. Replaying the games

The moves alone don't say what the board looks like at the end: stones get captured.
To know, you have to play the game through, checking after every move whether a group
has lost its last liberty. That is a loop with a flood fill inside, the kind of code no
built-in expression covers, so it goes in a callback: a function called on each value.

In Python this is `map_elements` with a function written in Python (it is in
`src/goboard.py`, about forty lines), and it is slow, because Python runs the loop. In
the Nim tab the same forty lines are Nim, compiled, and Nanuq 0.6 hands the bytes over
through the Arrow C Data Interface without copying them.

We replay the 3,997 complete games we kept (AlphaGo's, and all professional games
since 2025) and count the stones left and the stones captured.
"""

scene "s13_replay":
  type FinalCounts = object
    black_stones, white_stones, captured: int

  proc finalCounts(moves: string): FinalCounts =
    let (board, capturedByBlack, capturedByWhite) = goboard.replay(moves)
    FinalCounts(black_stones: board.count('\1'), white_stones: board.count('\2'),
                captured: capturedByBlack + capturedByWhite)

  let full = readParquet("data/pro_full_moves.parquet")
  let replayed = full.withColumns(col.moves.mapElements(finalCounts).alias("final")).unnest("final")
  echo replayed.select(col.file, col.PB, col.PW, col.RE, (col.moves.bin.size div 2).alias("n_moves"),
                       col.black_stones, col.white_stones, col.captured).sort(
    "captured", descending = true).head(5)

nbText: """
AlphaGo Zero playing itself leads the table: programs don't resign early, so their
games go on until every last group is settled. On a laptop the Python callback takes
about 3 seconds for these games, and the Nim one a few hundredths of a second. Here is
the bloodiest game between humans, at the end.
"""

figure "fig_bloodiest":
  let bloodiest = replayed.filter(not col.file.str.startsWith("AlphaGo/")).sort("captured", descending = true).head(1)
  let boardBytes = goboard.replay(bloodiest["moves", 0, string])[0]
  let finalStones = newDataFrame(series("cell", boardBytes.mapIt(it.int))).withRowIndex("p").filter(col.cell > 0).select(
    (col.p.cast(Int64) mod 19).alias("x"), (col.p.cast(Int64) div 19).alias("y"),
    `when`(col.cell == 1).then("B").otherwise("W").alias("color"))
  show plots.board(finalStones, bloodiest["PB", 0, string] & " (B) vs " & bloodiest["PW", 0, string] &
                   " (W), " & bloodiest["DT", 0, string] & ": final position")

nbText: """
And a sanity check across all games: the more moves a game has, the more stones get
captured, but the board never holds more than 361.
"""

scene "s13_check":
  echo replayed.select(
    len().alias("games"),
    (col.moves.bin.size div 2).mean.alias("mean_moves"),
    col.captured.mean.alias("mean_captured"),
    (col.black_stones + col.white_stones).max.alias("max_on_board"),
    corr(col.moves.bin.size, col.captured).alias("corr_moves_captured"),
  )

nbText: """
## Part 4: Italian go

## 14. Champions, in a database

Italy has played go seriously since the 1970s. The Italian Go Federation (FIGG) has
held a national championship every year since 1980; since 1992 the two best Italian
players of the championship tournament meet in a final. The federation's roll of honour
lists every winner, the score of the final and the runner-up. (2024 is missing from it;
the 2025 result comes from the federation's news.)

New in 0.6, frames go to and from **databases**: `write_database` creates a table,
`read_database` runs a SQL query and returns a frame. Here we use SQLite, a database in
a single file.
"""

scene "s14_db":
  let champions = readCsv("data/champions.csv")
  let db = open("italian_go.db", "", "", "")
  discard champions.writeDatabase("champions", db, ifTableExists = IfTableExists.Replace)
  db.close()
  let titles = readDatabaseUri("""
    SELECT winner AS player, COUNT(*) AS titles, MIN(year) AS first, MAX(year) AS last
    FROM champions GROUP BY winner ORDER BY titles DESC, first
    """, "sqlite://italian_go.db")
  withConfig(tblRows = -1):  # all fourteen
    echo titles

nbText: """
Fourteen champions in 45 championships, and the first six hold 34 titles between them.
The finals are long-running rivalries: some pairs met again and again.
"""

scene "s14_finals":
  echo readDatabaseUri("""
    SELECT winner, runner_up, COUNT(*) AS finals, GROUP_CONCAT(year, ' ') AS years
    FROM champions WHERE runner_up IS NOT NULL AND runner_up <> ''
    GROUP BY winner, runner_up HAVING COUNT(*) >= 2 ORDER BY finals DESC
    """, "sqlite://italian_go.db")

nbText: """
## 15. Fifty-six thousand players in a text file

The European Go Database records every rated tournament game in Europe. Its player list
is a plain text table with fixed-width columns: the PIN, the name (last name first),
country, club, grade, a suggested promotion, the rating (GoR), the number of
tournaments and the code of the last one (a letter, then the date as YYMMDD). We read each line as one string, keep the
lines that start with a PIN, and cut them at fixed positions.
"""

scene "s15_egd":
  let lines = readCsv("data/egd_players.txt", hasHeader = false, newColumns = ["line"], separator = '\x01').filter(
    col.line.str.contains(r"^ \d{8} "))
  proc cut(start, length: int): Expr =
    col.line.str.slice(start, length).str.stripChars

  let egd = lines.select(
    cut(0, 10).cast(Int64).alias("pin"),
    cut(11, 38).str.replaceAll("_", " ").alias("name"),
    cut(49, 2).alias("country"),
    cut(53, 4).alias("club"),
    cut(57, 6).alias("grade"),
    cut(68, 7).cast(Int64).alias("gor"),
    cut(75, 6).cast(Int64).alias("tournaments"),
    cut(83, 8).alias("last"),
  ).withColumns(col.last.str.slice(1, 2).str.toInteger(strict = false).alias("yy")).withColumns(
    `when`(col.yy > 50).then(1900 + col.yy).otherwise(2000 + col.yy).alias("last_year")
  ).drop("yy")
  echo egd.filter(col.country == "IT").sort("gor", descending = true).head(5)

nbText: """
How does Italy compare? Ratings work like chess Elo: 2100 is about 1 dan, and every 100
points is one grade. Among players active in the last five years:
"""

scene "s15_countries":
  echo egd.filter(col.last_year >= 2021).groupBy("country").agg(
    len().alias("players"), (col.gor >= 2050).sum.alias("dan"), col.gor.median.alias("median_gor"),
  ).filter(col.players >= 300).sort("players", descending = true).head(10)

nbText: """
## 16. The champions today, in a spreadsheet

Joining the roll of honour with the database gives each champion's current rating and
the number of tournaments they have played: some won the title and then stopped, others
are still playing forty years later. EGD writes names last name first, so we flip ours.
"""

scene "s16_join":
  let championCards = titles
    .withColumns(col.player.str.replace(r"^(\S+) (.+)$", "$2 $1").alias("name"))
    .join(egd.filter(col.country.isIn(["IT", "DE"])), on = ["name"], how = Left, maintainOrder = MaintainOrderJoin.Left)
    .select("player", "titles", "first", "last", "grade", "gor", "tournaments", "last_year")
  echo championCards

nbText: """
Spreadsheets are where results like this end up, so 0.6 also writes and reads **Excel**
files. `write_excel` makes a real `.xlsx` with a header row and autofit columns, and
`read_excel` reads a sheet back.
"""

scene "s16_excel":
  championCards.writeExcel("italian_champions.xlsx", worksheet = "champions", autofit = true)
  let back = readExcel("italian_champions.xlsx", sheetName = "champions")
  assertFrameEqual(back, championCards, checkDtypes = false)
  echo back.shape

nbText: """
## Afterword

Go players say that the board holds more positions than there are atoms in the
universe; a laptop with Polars can still hold every game humans have played on it. In
this post Nanuq streamed an 8 GB file it could not read at once, saved a query and used
it again on other data, counted komi in exact half points, searched moves stored as
bytes, hashed positions with XOR, replayed four thousand games in a Nim callback, and
moved tables in and out of SQLite and Excel.

AlphaGo retired in 2017. Its move 37 is still being played.
"""

nbText: """
## What this post used from Nanuq 0.6

- the streaming engine: `sinkParquet` on a `scanNdjson` with a schema, and
  `collect(Engine.InMemory)` to compare;
- `assertFrameEqual` from `nanuq/testing`;
- Decimal columns: `str.toDecimal`, casts to `Decimal(10, 1)`, grouping and arithmetic;
- Binary columns: the `bin` namespace (`size`, `get`, `slice`, `startsWith`, `encode`) and
  casts between Binary and String;
- bitwise expressions: `bitwiseXor`, `bitwiseAnd`, `bitwiseOr`, `bitwiseCountOnes`,
  `bitwiseLeadingZeros`;
- plan serialization: `e.meta.serialize(Json)` and `Expr.deserialize`;
- `fromEpoch`, `str.toInteger(base = 36)`;
- databases with `nanuq/database` (`writeDatabase`, `readDatabaseUri` on SQLite) and Excel
  files (`writeExcel`, `readExcel`);
- a Nim callback with `mapElements` on Binary values, returning an object as a struct.

The Python twin of this post, which recorded the outputs it is checked against, is
[blog/go/go.py](https://github.com/pietroppeter/nanuq/blob/main/docs/blog/go/go.py);
the figures are in [plots.nim](https://github.com/pietroppeter/nanuq/blob/main/docs/blog/go/plots.nim)
and [figs.py](https://github.com/pietroppeter/nanuq/blob/main/docs/blog/go/src/figs.py), the go
engine in [goboard.nim](https://github.com/pietroppeter/nanuq/blob/main/docs/blog/go/goboard.nim)
and [goboard.py](https://github.com/pietroppeter/nanuq/blob/main/docs/blog/go/src/goboard.py);
the data preparation scripts are in [src/](https://github.com/pietroppeter/nanuq/tree/main/docs/blog/go/src).

*Sources: Andries Brouwer's database of professional go games
(homepages.cwi.nl/~aeb/go/games); all public games on online-go.com, collected by Zachary
Vance with the permission of OGS (za3k.com/ogs); the roll of honour and news of the
Federazione Italiana Giuoco Go (figg.org); the player list of the European Go Database
(europeangodatabase.eu). Downloaded on 1 November 2026.*
"""

nbRawHtml: tabsScript()

setCurrentDir(siteDir)
nbSave
if mismatches.len > 0:
  quit "move_37: outputs differ from py-polars in: " & mismatches.join(", ")
