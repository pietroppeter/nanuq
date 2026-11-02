## Renders the whole site in one program: every dev-log post (docs/blog/*.nim), then
## the index, the Polars coverage map and the OpenSpec page. One compile and one link
## instead of one per page.
##
##   nim r docs/all.nim                 # the whole site
##   nim r docs/blog/move_37.nim        # one post, as before
##
## Each page renders when its module is initialised, in import order: posts by file
## name, then the index (it checks the rendered posts), coverage and OpenSpec pages.
## Posts are found at compile time, so a new one needs no list here.

import std/[macros, os, strutils, algorithm]

macro importPages(): untyped =
  let dir = currentSourcePath().parentDir
  var posts: seq[string]
  for line in staticExec("ls " & quoteShell(dir / "blog")).splitLines:
    if line.endsWith(".nim"): posts.add line[0 ..< ^4]
  posts.sort
  var src = ""
  # absolute paths: parseStmt has no file to be relative to
  for p in posts: src.add "import \"" & dir / "blog" / p & "\"\n"
  for p in ["index", "polars_coverage", "openspec"]: src.add "import \"" & dir / p & "\"\n"
  result = parseStmt(src)

{.warning[UnusedImport]: off.}
importPages()
