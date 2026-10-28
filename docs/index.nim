## The dev-log index: lists the rendered posts in docs/blog, newest first.
## Render the posts first; nothing here needs editing when a post is added.
import nimib
import std/[os, algorithm, re, strutils, times]
import nanuqtheme

nbInit
nb.title = "Nanuq dev log"
nb.useNanuqTheme(
  titleHtml = "Nanuq <em>dev log</em>",
  eyebrow = "Polars DataFrames for Nim",
  epigraph = "Watch out where the huskies go, and don't you eat that rusty data.",
  meta = "Rendered with nimib",
  summary = "Notes from building Nanuq, Polars DataFrames for Nim.",
)

type Post = object
  file, title, summary: string
  date: DateTime

proc unescape(s: string): string =
  s.multiReplace(("&quot;", "\""), ("&#x27;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&"))

proc escape(s: string): string =
  s.multiReplace(("&", "&amp;"), ("<", "&lt;"), (">", "&gt;"), ("\"", "&quot;"))

proc readPost(path: string): Post =
  ## Date and link from the dated file name, title from `<title>`, summary from
  ## the description meta tag the theme writes.
  let html = readFile(path)
  result.file = path.extractFilename
  result.date = parse(result.file[0 ..< 10], "yyyy-MM-dd")
  var m: array[1, string]
  if html.find(re"<title>([^<]*)</title>", m) >= 0: result.title = m[0].strip.unescape
  if html.find(re"""<meta name="description" content="([^"]*)">""", m) >= 0:
    result.summary = m[0].unescape

var posts: seq[Post]
for path in walkFiles("docs/blog/*.html"):  # nimib runs from the repo root
  if path.extractFilename.match(re"\d{4}-\d{2}-\d{2}-.*\.html"):
    posts.add readPost(path)
posts.sort(proc (a, b: Post): int = cmp(b.file, a.file))

nbText: """
Nanuq brings [Polars](https://pola.rs) DataFrames to Nim. These posts follow its
development, newest first. The code is on
[GitHub](https://github.com/pietroppeter/nanuq); official documentation will come later.
"""

var items = "<ol class=\"posts\">\n"
for p in posts:
  items.add "<li><time datetime=\"" & p.date.format("yyyy-MM-dd") & "\">" &
    p.date.format("d MMMM yyyy") & "</time>\n<a href=\"blog/" & p.file & "\">" &
    escape(p.title) & "</a>\n"
  if p.summary.len > 0: items.add "<p>" & escape(p.summary) & "</p>\n"
  items.add "</li>\n"
items.add "</ol>"
nbRawHtml: items

nbSave
