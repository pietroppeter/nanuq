## The dev-log index: lists the posts of docs/devlog.nim, newest first.
## Render the posts first. A new post is added in docs/devlog.nim, not here.
import nimib
import std/[os, algorithm, re, sequtils, strutils, times]
import nanuqtheme

nbInit
nb.title = "Nanuq dev log"
nb.useNanuqTheme(
  titleHtml = "Nanuq <em>dev log</em>",
  eyebrow = "Polars DataFrames for Nim",
  epigraph = "Watch out where the queries go, and process well that rusty data.",
  meta = "Rendered with nimib",
  summary = "Notes from building Nanuq, Polars DataFrames for Nim.",
  sourcePath = "docs/index.nim",
)

# Every listed post must have been rendered, and every rendered post must be listed,
# so a post can't be forgotten in docs/devlog.nim (nimib runs from docs/, see nimib.toml).
var rendered: seq[string]
for path in walkFiles("blog/*.html"):
  if path.extractFilename.match(re"\d{4}-\d{2}-\d{2}-.*\.html"):
    rendered.add path.extractFilename
for p in devlogPosts:
  if p.fileName notin rendered:
    quit "index: blog/" & p.fileName & " is listed in docs/devlog.nim but was not rendered"
for f in rendered:
  if devlogPosts.allIt(it.fileName != f):
    quit "index: blog/" & f & " is not listed in docs/devlog.nim"
# The README keeps its own list of posts.
let readme = readFile(".." / "README.md")
for p in devlogPosts:
  if "/blog/" & p.fileName notin readme:
    quit "index: README.md does not link blog/" & p.fileName

proc escape(s: string): string =
  s.multiReplace(("&", "&amp;"), ("<", "&lt;"), (">", "&gt;"), ("\"", "&quot;"))

nbText: """
Nanuq brings [Polars](https://pola.rs) DataFrames to Nim. These posts follow its
development, newest first. Since 0.2, each release gets an *API design* post on the choices it
made and an *explainer*, a playful story told with its new features. Every post links
to its source at the bottom. The code is on
[GitHub](https://github.com/pietroppeter/nanuq); official documentation will come later.
The [Polars coverage map](polars_coverage.html) shows which Polars features each release
covers.
"""

var items = "<ol class=\"posts\">\n"
for p in devlogPosts.reversed:
  let date = parse(p.date, "yyyy-MM-dd")
  items.add "<li><time datetime=\"" & p.date & "\">" & date.format("d MMMM yyyy") &
    " · <span class=\"kind\">" & $p.kind & " · Nanuq " & p.release & "</span></time>\n" &
    "<a href=\"blog/" & p.fileName & "\">" & p.titleHtml.multiReplace(("<em>", ""), ("</em>", "")).escape &
    "</a>\n<p>" & escape(p.summary) & "</p>\n</li>\n"
items.add "</ol>"
nbRawHtml: items

nbSave
