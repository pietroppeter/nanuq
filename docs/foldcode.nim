## Folded source code, after tabelline's `nbFoldCode` (pietroppeter/tabelline, docs/blocks.nim):
## a source file, or a part of it, folded under its path and its length, so a page can show
## every piece of code it talks about without its length getting in the way.
##
## A page collects them at its end, in a "Source files" section:
##
##   nbSourceFiles:
##     nbFoldCode "src/nanuq/ffi.nim", start = "when defined(nanuqLibPath)", stop = "proc ",
##                title = "`ffi.nim`: where the library comes from"
##     nbFoldCode "docs/blog/go/goboard.py"
##
## The Nanuq theme then says under the title that the section is there, and links every
## file name the text shows in code (`ffi.nim`, `src/nanuq/ffi.nim`) to its fold; a link to
## a fold opens it.

import std/[json, os, strutils, strformat]
import nimib

func esc(s: string): string = s.multiReplace(("&", "&amp;"), ("<", "&lt;"), (">", "&gt;"), ("\"", "&quot;"))
func inline(md: string): string = markdownToHtml(md).strip.replace("<p>", "").replace("</p>", "")

func foldId*(path: string): string =
  ## "docs/blog/go/goboard.py" -> "src-docs-blog-go-goboard-py"
  result = "src-"
  for c in path:
    if c in {'a'..'z', '0'..'9'}: result.add c
    elif c in {'A'..'Z'}: result.add c.toLowerAscii
    elif result[^1] != '-': result.add '-'
  result = result.strip(chars = {'-'}, leading = false)

proc langOf(file: string): string =
  case file.splitFile.ext
  of ".nim", ".nims", ".nimble": "nim"
  of ".py": "python"
  of ".rs": "rust"
  of ".js": "javascript"
  of ".yaml", ".yml": "yaml"
  of ".toml", ".ini", ".cfg": "ini"
  of ".json": "json"
  else: "bash"

newNbBlock(NbFoldCode):
  title: string
  path: string
  lang: string
  code: string
  id: string
  toHtml:
    let lines = blk.code.splitLines.len
    let name = if blk.title.len > 0: inline(blk.title) else: "<code>" & esc(blk.path) & "</code>"
    let body =
      if blk.lang == "nim": "<pre><code class=\"nohighlight nim hljs\">" & highlightNim(blk.code) & "</code></pre>"
      else: &"""<pre><code class="language-{blk.lang}">{esc(blk.code)}</code></pre>"""
    &"""<details class="foldcode" id="{blk.id}"><summary><span class="fc-name">{name}</span> """ &
      &"""<span class="fc-lines">{lines} lines</span></summary>{body}""" &
      &"""<p class="fc-path"><code>{esc(blk.path)}</code></p></details>"""

proc repoRootOf(file: string): string =
  var dir = file.parentDir
  while dir.len > 1 and not dirExists(dir / ".git") and not fileExists(dir / ".git"): dir = dir.parentDir
  if dirExists(dir / ".git") or fileExists(dir / ".git"): dir else: file.parentDir

proc foldCode*(nb: var Nb, file: string, start = "", stop = "", title = "", lang = "") =
  ## `file` (a path from the root of the page's repository, or from where the page runs),
  ## folded. With `start`, from the first line that holds it; with `stop`, up to the next line
  ## that holds that (or to the end).
  let root = repoRootOf(nb.doc.thisFile.string)
  let path = if fileExists(root / file): root / file else: absolutePath(file)
  doAssert fileExists(path), "nbFoldCode: no file " & file
  var code = readFile(path)
  if start.len > 0:
    let i = code.find(start)
    doAssert i >= 0, file & ": no " & start
    code = code[code.rfind('\n', last = i) + 1 .. ^1]
  if stop.len > 0:
    let j = code.find(stop, start = code.find('\n') + 1)
    if j >= 0: code = code[0 ..< code.rfind('\n', last = j) + 1]
  let rel = relativePath(path, root).replace('\\', '/')
  var folds = nb.doc.context{"folds"}
  if folds.isNil: folds = newJArray()
  var id = foldId(rel)
  var n = 1
  for f in folds:
    if f["path"].getStr == rel: inc n
  if n > 1: id.add "-" & $n   # a second part of the same file
  folds.add %*{"id": id, "path": rel}
  nb.doc.context["folds"] = folds
  nb.add newNbFoldCode(title = title, path = rel, lang = (if lang.len > 0: lang else: langOf(file)),
                       code = code.dedent.strip(chars = {'\n'}), id = id)

template nbFoldCode*(file: string, start = "", stop = "", title = "", lang = "") =
  ## Code folded under its path (or `title`, in Markdown) and its length:
  ## `nbFoldCode "src/nanuq/ffi.nim"`, or a part of it with `start` and `stop`.
  nb.foldCode(file, start, stop, title, lang)

const sourceFilesIntro* = "Every source file this page mentions, folded: tap one to read it. " &
  "A file's name in the text leads here."

template nbSourceFiles*(body: untyped) =
  ## The "Source files" section, at the end of a page: a heading, a line, then the folds
  ## `body` adds. The theme points to it from the top of the page.
  nb.doc.context["source_files"] = %true
  nbText: "## Source files\n\n" & sourceFilesIntro
  body

func linkMentions*(html: string, folds: JsonNode): string =
  ## Links each file name shown as inline code (`<code>ffi.nim</code>`) to its fold: the fold
  ## whose path is the name, or ends with "/" and the name. Code blocks, links and the folds
  ## themselves are left alone.
  if folds.isNil or folds.len == 0: return html
  proc target(name: string): string =
    for f in folds:
      let p = f["path"].getStr
      if p == name or p.endsWith("/" & name): return f["id"].getStr
  var i = 0
  while true:
    let s = html.find("<code>", i)
    if s < 0: break
    let e = html.find("</code>", s)
    if e < 0: break
    let name = html[s + 6 ..< e]
    result.add html[i ..< s]
    let inLink = html.rfind("<a ", last = s) > html.rfind("</a>", last = s)
    let inFold = html.rfind("<details class=\"foldcode\"", last = s) > html.rfind("</details>", last = s)
    let id = if inLink or inFold or '<' in name or ' ' in name: "" else: target(name)
    if id.len > 0: result.add &"""<a class="to-fold" href="#{id}"><code>{name}</code></a>"""
    else: result.add html[s ..< e + 7]
    i = e + 7
  result.add html[i .. ^1]

const foldCss* = """
/* code, folded under its name and its length (foldcode.nim) */
details.foldcode { margin: 0; border-top: 1px solid var(--rule); border-bottom: 1px solid var(--rule); }
details.foldcode + details.foldcode { border-top: 0; }
details.foldcode:not(:has(+ details.foldcode)) { margin-bottom: 1.6rem; }
details.foldcode > summary { list-style: none; cursor: pointer; min-height: 44px; padding: .5rem 0; display: flex; gap: .6rem;
  align-items: baseline; font: .85rem/1.4 var(--mono); }
details.foldcode > summary::-webkit-details-marker { display: none; }
details.foldcode > summary::before { content: "+"; font-weight: 700; width: .8rem; flex: none; color: var(--fjord); }
details.foldcode[open] > summary::before { content: "−"; }
details.foldcode .fc-name { overflow-wrap: anywhere; }
details.foldcode .fc-name code { background: none; padding: 0; font-size: 1em; }
details.foldcode .fc-lines { margin-left: auto; font-size: .75rem; color: var(--mute); white-space: nowrap; }
details.foldcode pre:has(> code) { margin: .2rem 0 .4rem; max-height: 70vh; overflow: auto; }
details.foldcode pre > code { font-size: .78rem; }
details.foldcode .fc-path { margin: 0 0 .8rem; font: .72rem/1.4 var(--mono); color: var(--mute); }
details.foldcode .fc-path code { background: none; padding: 0; }
pre:has(> code.language-python)::before { content: "python"; }
pre:has(> code.language-bash)::before { content: "shell"; }
pre:has(> code.language-ini)::before { content: "toml"; }
pre:has(> code.language-yaml)::before { content: "yaml"; }
pre:has(> code.language-javascript)::before { content: "js"; }
pre:has(> code.language-json)::before { content: "json"; }
details.foldcode pre:has(> code)::before { content: none !important; }
details.foldcode pre:has(> code) { padding-top: .9rem; }
a.to-fold { text-decoration-style: dotted; }
.source-files-note { margin: .2rem 0 0; font: .8rem/1.4 var(--mono); color: var(--mute); }
"""

const foldJs* = """
<script>
(function () {
  // a link to a fold, or to something inside one, opens it, then goes there
  function reveal() {
    var id = decodeURIComponent(location.hash.slice(1));
    var el = id && document.getElementById(id);
    if (!el) return;
    var shut = false;
    for (var d = el.closest('details'); d; d = d.parentElement && d.parentElement.closest('details')) {
      if (!d.open) { d.open = true; shut = true; }
    }
    if (shut) el.scrollIntoView();
  }
  window.addEventListener('hashchange', reveal);
  reveal();
})();
</script>
"""
