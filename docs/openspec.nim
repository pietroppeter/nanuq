## The OpenSpec page: every spec in openspec/specs and every change, open or archived,
## as tools/specview.nim shows them, inside the dev-log theme. A living page, not a
## dated post: CI rebuilds it whenever openspec/ changes on main. Nothing here needs Nanuq.
import nimib
import std/[json, osproc, strutils, times]
import nanuqtheme
import ../tools/specview

nbInit
# nimib runs from docs/ (see nimib.toml), so the repository is one level up.
let report = loadReport("..")
proc lastChange(path: string): string =
  ## "2 November 2026": the date of the last commit that touched `path`.
  let (d, code) = execCmdEx("git -C .. log -1 --format=%cs -- " & path)
  if code == 0 and d.strip.len > 0: d.strip.parse("yyyy-MM-dd").format("d MMMM yyyy")
  else: now().format("d MMMM yyyy")

nb.title = "Specs and changes"
nb.useNanuqTheme(
  titleHtml = "Specs and <em>changes</em>",
  eyebrow = """<a href="index.html">Nanuq dev log</a> · OpenSpec · updated """ &
    lastChange("openspec"),
  epigraph = "Watch out where the queries go, and process well that rusty data.",
  meta = "Living page, rebuilt when openspec/ changes · at " & report.head &
    " · rendered with tools/specview.nim and nimib",
  summary = "How Nanuq behaves today (its OpenSpec specs) and every change that got it there.",
  sourcePath = "docs/openspec.nim",
)
nb.doc.context["devlog_nav"] = %("""<nav class="devlog" aria-label="More from the dev log">""" &
  """<span class="links"><a href="index.html">All posts</a> · <a href="polars_coverage.html">Polars coverage</a> · """ &
  """<a href="https://github.com/pietroppeter/nanuq/tree/main/openspec">openspec/ on GitHub</a></span></nav>""" & "\n")

proc scoped(css, scope: string): string =
  ## Prefixes every selector of the flat stylesheet `css` with `scope`, so the report's
  ## rules for details, tables and pills don't reach the theme's header and footer.
  ## Rules on `body` (the archived toggle) are kept as they are.
  for rule in css.split('}'):
    let parts = rule.split('{', maxsplit = 1)
    if parts.len < 2: continue
    var sels: seq[string]
    for sel in parts[0].split(','):
      let s = sel.strip
      sels.add(if s.startsWith("body"): s else: scope & " " & s)
    result.add sels.join(",") & "{" & parts[1] & "}\n"

nbRawHtml: """<style>
body > header, body > main, body > footer { max-width: 62rem; }
:root { --add: #e3f4e6; --add-ink: #1f6b2c; --del: #fbe7e4; --del-ink: #a2321f; --mod: #fff2d6; --mod-ink: #8a5a00; }
@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) {
  --add: #12301b; --add-ink: #8fd19a; --del: #3a1a16; --del-ink: #f0a092; --mod: #33290f; --mod-ink: #f0c868; } }
:root[data-theme="dark"] { --add: #12301b; --add-ink: #8fd19a; --del: #3a1a16; --del-ink: #f0a092; --mod: #33290f; --mod-ink: #f0c868; }
@media (min-width: 48rem) { .specview table.overview, .specview table.diff { display: table; } }
.specview .nav { margin-bottom: 1rem; }
.specview pre:has(> code) { background: var(--floe); border-style: solid; padding: .8rem; margin: .5rem 0; }
.specview pre:has(> code)::before { content: none; }
.specview pre.out:has(> code) { background: var(--ice); border-style: dashed; padding-top: 1.4rem; }
.specview pre.out:has(> code)::before { content: "output"; }
""" & scoped(reportCss, ".specview") & "</style>"

nbText: """
Nanuq plans its work with [OpenSpec](https://github.com/Fission-AI/OpenSpec).
The **specs** in `openspec/specs/` describe how Nanuq behaves today: one per capability,
each requirement with a Nim example, its output and the scenarios it must pass. A
**change** proposes new behavior: a proposal (with its differences from Polars), spec
deltas, sometimes a design, and tasks. Once implemented, it is archived and its deltas
are merged into the specs. The
[README](https://github.com/pietroppeter/nanuq#how-development-works) explains the
process.

Below, first the changes (open ones first; tick the box to see the archived ones, each
with its proposal, spec deltas and revisions), then every spec in full. Ideas not yet
picked up wait in
[BACKLOG.md](https://github.com/pietroppeter/nanuq/blob/main/BACKLOG.md).
"""

nbRawHtml: "<div class=\"specview\">" & renderNav(report) & renderReport(report) & "</div>" & toggleJs

nbSave
