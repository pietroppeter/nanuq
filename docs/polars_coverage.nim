## The Polars coverage map: every Polars feature group and where the latest Nanuq
## release stands, plus what the next release plans. A living page, not a dated post:
## the data is docs/coverage/polars.json, refreshed in each release PR (see the dev-log
## spec). Nothing here needs Nanuq.
import nimib
import std/[json, strutils, tables, algorithm, times]
import nanuqtheme

nbInit
let data = parseFile("coverage/polars.json")  # nimib runs from docs/ (see nimib.toml)
let release = data["release"]["version"].getStr
let next = if data.hasKey("next"): data["next"]["version"].getStr else: ""
proc longDate(iso: string): string = iso.parse("yyyy-MM-dd").format("d MMMM yyyy")
nb.title = "Polars coverage"
nb.useNanuqTheme(
  titleHtml = "Polars features and what <em>Nanuq</em> covers",
  eyebrow = """<a href="index.html">Nanuq dev log</a> · Coverage map · updated """ &
    longDate(data["updated"].getStr),
  epigraph = "Watch out where the queries go, and process well that rusty data.",
  meta = "Living page, refreshed with each release · Nanuq " & release & " · " &
    data["polars"].getStr & " · rendered with nimib",
  summary = "Every Polars feature group and its status in the latest Nanuq release.",
  sourcePath = "docs/polars_coverage.nim",
)
# Footer like the posts': the API design post of the release, the index, the data.
block:
  var design: seq[string]
  for p in devlogPosts:
    if p.kind == ApiDesign and p.release == release:
      design.add "<a href=\"blog/" & p.fileName & "\">" & p.plainTitle & "</a>"
  nb.doc.context["devlog_nav"] = %("""<nav class="devlog" aria-label="More from the dev log">""" &
    (if design.len > 0: """<p class="rel"><span>How these APIs were chosen:</span> """ &
      design.join(", ") & "</p>" else: "") &
    """<span class="links"><a href="index.html">All posts</a> · <a href="openspec.html">Specs and changes</a> · """ &
    """<a href="https://github.com/pietroppeter/nanuq/blob/main/docs/coverage/polars.json">The data on GitHub</a></span></nav>""" & "\n")

proc esc(s: string): string =
  s.multiReplace(("&", "&amp;"), ("<", "&lt;"), (">", "&gt;"), ("\"", "&quot;"))

const labels = {"done": "has it", "partial": "partly", "missing": "missing",
                "no": "not planned"}.toTable
const order = ["done", "partial", "missing", "no"]

proc pill(r: JsonNode): string =
  ## A ringed pill is new in this release.
  let s = r["status"].getStr
  "<span class=\"pill " & s & (if r{"new"}.getBool: " changed" else: "") & "\">" & labels[s] & "</span>"

proc plannedCell(r: JsonNode): string =
  if r.hasKey("planned"): "<span class=\"plan\">" & esc(r["planned"].getStr) & "</span>" else: ""

proc counts(rows: seq[JsonNode]): CountTable[string] =
  for r in rows:
    result.inc r["status"].getStr
    if r{"new"}.getBool: result.inc "new"
    if r{"planned"}.getStr == next and next.len > 0: result.inc "planned"

var allRows: seq[JsonNode]
for a in data["areas"]:
  for r in a["rows"]: allRows.add r
# The Planned column appears only once a next release has a plan ("next" in the data,
# "planned" on rows).
let showPlanned = next.len > 0
proc plannedTh(): string = (if showPlanned: "<th class=\"st\">Planned</th>" else: "")
proc plannedTd(r: JsonNode): string = (if showPlanned: "<td class=\"st\">" & plannedCell(r) & "</td>" else: "")

nbRawHtml: """<style>
body > header, body > main, body > footer { max-width: 68rem; }
.cov-tiles { display: grid; grid-template-columns: repeat(auto-fit, minmax(14rem, 1fr)); gap: .8rem; margin: 1.2rem 0; }
.cov-tile { background: var(--floe); border: 1px solid var(--rule); border-radius: 6px; padding: .9rem 1rem; min-width: 0; }
.cov-tile h3 { margin: 0; font-size: 1rem; } .cov-tile .ref { font: .72rem/1.4 var(--mono); color: var(--mute); }
.cov-tile .n { font: 700 2rem/1.1 var(--display); font-variant-numeric: tabular-nums; margin-top: .4rem; }
.cov-tile .l { font: .72rem/1.4 var(--mono); color: var(--mute); }
.cov-bar { display: flex; height: .55rem; border-radius: 999px; overflow: hidden; border: 1px solid var(--rule); margin-top: .6rem; }
.cov-bar span { display: block; height: 100%; }
.cov-bar .done { background: var(--str); } .cov-bar .partial { background: var(--num); }
.cov-bar .missing { background: var(--kw); } .cov-bar .no { background: var(--com); }
.pill { display: inline-block; font: 600 .66rem/1 var(--mono); letter-spacing: .06em; text-transform: uppercase;
  padding: .3em .55em; border-radius: 999px; white-space: nowrap; border: 1px solid transparent; }
.pill.done { color: var(--str); border-color: var(--str); }
.pill.partial { color: var(--num); border-color: var(--num); }
.pill.missing { color: var(--kw); border-color: var(--kw); border-style: dashed; }
.pill.no { color: var(--com); border-color: var(--rule); }
.pill.changed { box-shadow: 0 0 0 2px var(--out-bg), 0 0 0 3px var(--fjord); }
.legend { display: flex; flex-wrap: wrap; gap: .5rem 1rem; align-items: center; font: .78rem/1.4 var(--mono); color: var(--mute); }
table.cov td.st, table.cov th.st { min-width: 0; white-space: nowrap; }
table.cov td.feat { font: 600 .9rem/1.35 var(--display); min-width: 10rem; }
table.cov td.names { font: .76rem/1.45 var(--mono); color: var(--mute); min-width: 14rem; }
table.cov td.note { min-width: 18rem; }
table.cov td.num { min-width: 0; font-variant-numeric: tabular-nums; text-align: right; }
.diff { border-left: 3px solid var(--fjord); padding-left: 1rem; color: var(--mute); margin: .8rem 0; }
.toc { columns: 2; column-gap: 2rem; } .toc li { break-inside: avoid; }
@media (max-width: 36rem) { .toc { columns: 1; } }
.plan { font: 600 .72rem/1 var(--mono); color: var(--fjord); }
</style>"""

nbText: """
Polars has about a thousand public entry points. This page groups them into feature
groups and says whether the latest Nanuq release **has it**, has it **partly** (fewer
options or types than Polars), is **missing** it, or does **not plan** it (Python-only
features, or ones without a Nim counterpart). Notes name what is still missing inside a
group. A ringed status is new in this release. Once the next release has a plan, open
groups also show the release that plans them.

The data lives in
[docs/coverage/polars.json](https://github.com/pietroppeter/nanuq/blob/main/docs/coverage/polars.json)
and is refreshed in each release PR. Names on this page are Polars' Python names; Nanuq
uses the same names in camelCase. The [dev log](index.html) explains the design choices.
"""

let c = counts(allRows)
let total = allRows.len
var tiles = "<div class=\"cov-tiles\"><div class=\"cov-tile\"><h3>Nanuq " & release &
  "</h3><div class=\"ref\">" & esc(data["release"]["tag"].getStr) & " · released " &
  longDate(data["release"]["date"].getStr) & "</div>"
tiles.add "<div class=\"n\">" & $c["done"] & " <span class=\"l\">of " & $total &
  " groups</span></div><div class=\"l\">" & $c["partial"] & " partly · " & $c["missing"] &
  " missing · " & $c["no"] & " not planned · " & $c["new"] & " new in " & release & "</div>"
tiles.add "<div class=\"cov-bar\" role=\"img\" aria-label=\"" & $c["done"] & " of " & $total & " done\">"
for s in order:
  tiles.add "<span class=\"" & s & "\" style=\"width:" & formatFloat(100 * c[s] / total, ffDecimal, 1) & "%\"></span>"
tiles.add "</div></div>"
if next.len > 0:
  tiles.add "<div class=\"cov-tile\"><h3>Nanuq " & next & "</h3><div class=\"ref\">next release</div>" &
    "<div class=\"n\">" & $c["planned"] & " <span class=\"l\">open groups planned</span></div>" &
    "<div class=\"l\">" & esc(data["next"]["plan"].getStr) & "</div></div>"
tiles.add "</div>"
nbRawHtml: tiles

nbText: "## By area"
var byArea = "<table class=\"cov\"><thead><tr><th>Area</th><th class=\"st\">Groups</th>" &
  "<th class=\"st\">Has it</th><th class=\"st\">Partly</th><th class=\"st\">Missing</th>" &
  "<th class=\"st\">New in " & release & "</th></tr></thead><tbody>"
for a in data["areas"]:
  var rows: seq[JsonNode]
  for r in a["rows"]: rows.add r
  let c = counts(rows)
  byArea.add "<tr><td class=\"feat\"><a href=\"#" & a["id"].getStr & "\">" & esc(a["title"].getStr) &
    "</a></td><td class=\"num\">" & $rows.len & "</td><td class=\"num\">" & $c["done"] &
    "</td><td class=\"num\">" & $c["partial"] & "</td><td class=\"num\">" & $c["missing"] &
    "</td><td class=\"num\">" & $c["new"] & "</td></tr>"
byArea.add "</tbody></table>"
nbRawHtml: byArea

nbText: "## Still open" & """

Groups not fully covered in """ & release & """, by priority: P1 next, P2 after,
P3 when someone needs it. Ideas that are picked up go through OpenSpec; the rest wait in
[BACKLOG.md](https://github.com/pietroppeter/nanuq/blob/main/BACKLOG.md).
"""
var open: seq[(string, string, JsonNode)]
for a in data["areas"]:
  for r in a["rows"]:
    if r["status"].getStr in ["partial", "missing"]:
      open.add (r{"priority"}.getStr("P3"), a["title"].getStr, r)
open.sort(proc (x, y: (string, string, JsonNode)): int = cmp(x[0], y[0]))
var openHtml = "<table class=\"cov\"><thead><tr><th class=\"st\">Prio</th><th>Feature group</th>" &
  "<th class=\"st\">" & release & "</th>" & plannedTh() & "<th>Area</th><th>What is missing</th></tr></thead><tbody>"
for (p, area, r) in open:
  openHtml.add "<tr><td class=\"st\">" & p & "</td><td class=\"feat\">" & esc(r["feature"].getStr) &
    "</td><td class=\"st\">" & pill(r) & "</td>" & plannedTd(r) &
    "<td class=\"names\">" & esc(area) & "</td><td class=\"note\">" & esc(r["note"].getStr) & "</td></tr>"
openHtml.add "</tbody></table>"
nbRawHtml: openHtml

nbText: "## Catalogue"
var legend = "<div class=\"legend\">"
for s in order: legend.add pill(%*{"status": s})
legend.add pill(%*{"status": "done", "new": true}) & "<span>new in " & release & "</span></div>"
var toc = "<ol class=\"toc\">"
for a in data["areas"]:
  toc.add "<li><a href=\"#" & a["id"].getStr & "\">" & esc(a["title"].getStr) & "</a></li>"
toc.add "</ol>"
nbRawHtml: legend & toc

for a in data["areas"]:
  var h = "<h3 id=\"" & a["id"].getStr & "\">" & esc(a["title"].getStr) & "</h3><p>" & esc(a["intro"].getStr) & "</p>"
  h.add "<table class=\"cov\"><thead><tr><th>Feature group</th><th class=\"st\">" & release &
    "</th>" & plannedTh() & "<th>Polars names</th><th>Notes</th></tr></thead><tbody>"
  for r in a["rows"]:
    h.add "<tr><td class=\"feat\">" & esc(r["feature"].getStr) & "</td><td class=\"st\">" & pill(r) &
      "</td>" & plannedTd(r) & "<td class=\"names\">" & esc(r["polars"].getStr) &
      "</td><td class=\"note\">" & esc(r["note"].getStr) & "</td></tr>"
  h.add "</tbody></table>"
  if a["differences"].getStr.len > 0:
    h.add "<div class=\"diff\"><b>Differences from Polars.</b> " & esc(a["differences"].getStr) & "</div>"
  nbRawHtml: h

nbSave
