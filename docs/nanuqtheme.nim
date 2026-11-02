## A nimib theme for the Nanuq docs: pack-ice palette, light and dark,
## self-contained apart from Google Fonts and highlight.js for Rust snippets.
##
## Usage, right after `nbInit`, for a dev-log post listed in devlog.nim:
##   nb.useDevlogPost("above-4000", epigraph = "...")
## and for any other page:
##   nb.useNanuqTheme(titleHtml = "...", eyebrow = "...", epigraph = "...", meta = "...")

import std/[json, os, strformat, strutils]
import nimib
import devlog
export devlog

const nanuqHead = """
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Familjen+Grotesk:wght@500;700&family=Literata:ital,opsz,wght@0,7..72,400;0,7..72,600;1,7..72,400&family=JetBrains+Mono:wght@400;600&display=swap">
<link rel="icon" href="data:image/svg+xml,<svg xmlns=%22http://www.w3.org/2000/svg%22 viewBox=%220 0 100 100%22><text y=%22.9em%22 font-size=%2280%22>🐻‍❄️</text></svg>">
<style>
/* Layout: one reading column on pack-ice ground; code and output read as a notebook cell pair. */
:root {
  --ice: #f3f7f9;        /* page ground */
  --floe: #ffffff;       /* code surface */
  --ink: #12222e;        /* text */
  --mute: #5a6b77;       /* secondary text */
  --rule: #d5e1e8;       /* borders */
  --fjord: #0d6f86;      /* accent */
  --out-bg: #e8f0f4;     /* output surface */
  --kw: #8a3b8f; --str: #2f7a3a; --num: #a55310; --com: #7b8a95; --fn: #0d6f86;
  --display: "Familjen Grotesk", "Helvetica Neue", Arial, sans-serif;
  --body: "Literata", Georgia, "Times New Roman", serif;
  --mono: "JetBrains Mono", ui-monospace, "SF Mono", Menlo, Consolas, monospace;
  color-scheme: light;
}
@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) {
    --ice: #0d161d; --floe: #121e27; --ink: #e3ecf1; --mute: #93a6b3; --rule: #22323e;
    --fjord: #5cc4dc; --out-bg: #0a1218;
    --kw: #d79be0; --str: #8fd19a; --num: #f0a868; --com: #6d8190; --fn: #5cc4dc;
    color-scheme: dark;
  }
}
:root[data-theme="dark"] {
  --ice: #0d161d; --floe: #121e27; --ink: #e3ecf1; --mute: #93a6b3; --rule: #22323e;
  --fjord: #5cc4dc; --out-bg: #0a1218;
  --kw: #d79be0; --str: #8fd19a; --num: #f0a868; --com: #6d8190; --fn: #5cc4dc;
  color-scheme: dark;
}
* { box-sizing: border-box; }
body {
  margin: 0; background: var(--ice); color: var(--ink);
  font: 17px/1.65 var(--body);
  padding-left: max(16px, env(safe-area-inset-left, 0px));
  padding-right: max(16px, env(safe-area-inset-right, 0px));
}
body > header, body > main, body > footer { max-width: 46rem; margin: 0 auto; }
body > header { padding-block: 3rem 0; }
body > footer { padding-block: 1rem 4rem; }
.mast { display: grid; gap: .6rem; padding-bottom: 2rem; border-bottom: 1px solid var(--rule); margin-bottom: 1rem; }
.eyebrow { font: 600 .75rem/1 var(--mono); letter-spacing: .12em; text-transform: uppercase; color: var(--fjord); }
.mast h1 { font: 700 clamp(2.4rem, 7vw, 3.6rem)/1.02 var(--display); letter-spacing: -.02em; margin: 0; text-wrap: balance; }
.eyebrow a { color: inherit; text-decoration: none; }
.eyebrow a:hover { text-decoration: underline; }
.mast h1 em { font-style: normal; color: var(--fjord); }
.epigraph { font-style: italic; color: var(--mute); margin: 0; }
.meta { font: .8rem/1.4 var(--mono); color: var(--mute); }
h2, h3 { font-family: var(--display); text-wrap: balance; line-height: 1.15; }
h2 { font-size: 1.7rem; font-weight: 700; margin: 2.8rem 0 .6rem; letter-spacing: -.01em; }
h3 { font-size: 1.2rem; font-weight: 700; margin: 2rem 0 .4rem; }
p, li { max-width: 65ch; }
a { color: var(--fjord); text-underline-offset: 2px; }
a:focus-visible { outline: 2px solid var(--fjord); outline-offset: 2px; border-radius: 2px; }
code, pre { font-family: var(--mono); }
pre, pre *, code { font-variant-ligatures: none !important; } /* show >= as typed */
code { font-size: .86em; }
p code, li code { background: var(--out-bg); padding: .1em .3em; border-radius: 3px; }
pre { margin: 0; overflow-x: auto; }
pre:has(> code) {
  position: relative; background: var(--floe); border: 1px solid var(--rule);
  border-radius: 6px; padding: 1.6rem 1rem .9rem; margin: 1.2rem 0 0; font-size: .85rem; line-height: 1.55;
}
pre:has(> code)::before {
  position: absolute; top: .45rem; right: .7rem;
  font: 600 .65rem/1 var(--mono); letter-spacing: .1em; text-transform: uppercase; color: var(--mute);
}
pre:has(> code.nohighlight.nim)::before { content: "nim · ran"; }
pre:has(> code.language-nim)::before { content: "nim"; }
pre:has(> code.language-rust)::before { content: "rust"; }
pre:has(> code:not([class]))::before { content: "layout"; }
pre:has(> code.nim-source)::before { content: "nim · source of this page"; }
pre:has(> code:not([class])) { background: transparent; border-style: dashed; }
pre:has(> code.nohighlight.nim):has(+ pre.nb-output) { border-radius: 6px 6px 0 0; }
pre.nb-output {
  background: var(--out-bg); border: 1px solid var(--rule); border-top: none; border-radius: 0 0 6px 6px;
  padding: 1.6rem 1rem .9rem; position: relative;
  font: .8rem/1.2 var(--mono); color: var(--ink); white-space: pre;
}
pre.nb-output::before {
  content: "output"; position: absolute; top: .55rem; left: 1rem;
  font: 600 .65rem/1 var(--mono); letter-spacing: .1em; text-transform: uppercase; color: var(--fjord);
}
.hljs-keyword, .hljs-meta, .hljs-built_in { color: var(--kw); }
.hljs-string, .hljs-char { color: var(--str); }
.hljs-number, .hljs-literal { color: var(--num); }
.hljs-comment { color: var(--com); font-style: italic; }
.hljs-title, .hljs-function, .hljs-type { color: var(--fn); }
.hljs-attribute, .hljs-symbol, .hljs-variable { color: var(--ink); }
figure { margin: 1.2rem 0; }
figure img { display: block; max-width: 100%; height: auto; border: 1px solid var(--rule); border-radius: 6px; }
figcaption { font: .8rem/1.4 var(--mono); color: var(--mute); margin-top: .4rem; }
blockquote { border-left: 3px solid var(--fjord); margin: 1rem 0; padding-left: 1rem; color: var(--mute); }
ul { padding-left: 1.2rem; }
/* wide tables scroll inside themselves, never the page */
table { display: block; overflow-x: auto; border-collapse: collapse; margin: 1.2rem 0; font-size: .85rem; line-height: 1.45;
  border: 1px solid var(--rule); border-radius: 6px; background: var(--floe); }
th, td { text-align: left; vertical-align: top; padding: .55rem .7rem; border-bottom: 1px solid var(--rule); min-width: 9rem; }
th { font: 600 .68rem/1.2 var(--mono); letter-spacing: .08em; text-transform: uppercase; color: var(--mute); background: var(--out-bg); }
tr:last-child td { border-bottom: none; }
td code { background: var(--out-bg); padding: .1em .3em; border-radius: 3px; }
/* toHtml tables (Polars' notebook HTML): compact, monospace, right-aligned like the text table */
table.dataframe { font: .78rem/1.4 var(--mono); width: max-content; max-width: 100%; margin-top: .3rem; }
small:has(+ table.dataframe) { font: .72rem/1.4 var(--mono); color: var(--mute); }
table.dataframe th, table.dataframe td { min-width: 0; padding: .3rem .6rem; text-align: right; white-space: pre; }
table.dataframe th { font: 600 .78rem/1.4 var(--mono); letter-spacing: 0; text-transform: none; color: var(--ink); }
table.dataframe thead tr:nth-child(2) td { color: var(--mute); background: var(--out-bg); border-bottom: 2px solid var(--rule); }
/* the dev-log index */
ol.posts { list-style: none; padding: 0; margin: 2rem 0; }
ol.posts li { padding: 1rem 0; border-bottom: 1px solid var(--rule); }
ol.posts li:last-child { border-bottom: none; }
ol.posts time { display: block; font: .72rem/1.4 var(--mono); letter-spacing: .06em; color: var(--mute); text-transform: uppercase; }
ol.posts a { font: 700 1.25rem/1.3 var(--display); color: var(--ink); text-decoration: none; }
ol.posts a:hover { color: var(--fjord); }
ol.posts p { margin: .3rem 0 0; color: var(--mute); }
/* the end of a post: previous and next post, related posts, where the source lives */
nav.devlog { margin-top: 3rem; padding-top: 1.2rem; border-top: 1px solid var(--rule); display: grid; gap: 1rem; }
nav.devlog .pn { display: grid; grid-template-columns: 1fr 1fr; gap: 1rem; }
nav.devlog .pn a { display: block; padding: .8rem 1rem; border: 1px solid var(--rule); border-radius: 6px;
  background: var(--floe); text-decoration: none; color: var(--ink); font: 700 1rem/1.3 var(--display); }
nav.devlog .pn a:hover { border-color: var(--fjord); color: var(--fjord); }
nav.devlog .pn a.next { grid-column: 2; text-align: right; }
nav.devlog .pn small { display: block; font: 600 .65rem/1.4 var(--mono); letter-spacing: .1em; text-transform: uppercase; color: var(--mute); margin-bottom: .2rem; }
nav.devlog .rel { margin: 0; }
nav.devlog .rel span, nav.devlog .links { font: .8rem/1.6 var(--mono); color: var(--mute); }
@media (max-width: 34rem) { nav.devlog .pn { grid-template-columns: 1fr; } nav.devlog .pn a.next { grid-column: 1; } }
ol.posts .kind { color: var(--fjord); }
/* "Show source": the page's own nimib source, folded at the end */
details.source { margin-top: 3rem; }
details.source summary { cursor: pointer; width: max-content; font: 600 .75rem/1 var(--mono); letter-spacing: .06em;
  text-transform: uppercase; color: var(--fjord); padding: .5rem .8rem; border: 1px solid var(--rule); border-radius: 6px; background: var(--floe); }
details.source summary::marker { content: ""; }
details.source summary::before { content: "Show source"; }
details.source[open] summary::before { content: "Hide source"; }
details.source pre { margin-top: 1rem; }
footer .foot { margin-top: 3rem; padding-top: 1rem; border-top: 1px solid var(--rule); font: .8rem/1.5 var(--mono); color: var(--mute); }
</style>
"""

const nanuqScripts = """
<script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/languages/rust.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/languages/nim.min.js"></script>
<script>
  if (window.hljs) document.querySelectorAll("code.language-rust, code.language-nim").forEach(el => {
    try { hljs.highlightElement(el); } catch (e) {}
  });
</script>
"""

func nanuqHeader(blk: JsonNode, nb: Nb): string =
  let c = nb.doc.context
  let (eyebrow, title, epigraph, meta) = (c{"eyebrow"}.getStr, c{"title_html"}.getStr,
                                          c{"epigraph"}.getStr, c{"meta"}.getStr)
  &"""<header class="mast">
  <span class="eyebrow">{eyebrow}</span>
  <h1>{title}</h1>
  <p class="epigraph">{epigraph}</p>
  <span class="meta">{meta}</span>
</header>"""

func nanuqFooter(blk: JsonNode, nb: Nb): string =
  ## Previous/next and related posts, then a folded "Show source" section, like
  ## nimib's default theme.
  let source = nb.doc.context{"source_highlighted"}.getStr
  let sourcePath = nb.doc.context{"source_path"}.getStr
  let sourceLink =
    if sourcePath.len == 0: &"""<a href="{repoUrl}">pietroppeter/nanuq</a>"""
    else: &"""<a href="{sourceUrl}{sourcePath}">{sourcePath}</a> in <a href="{repoUrl}">pietroppeter/nanuq</a>"""
  "<footer>" & nb.doc.context{"devlog_nav"}.getStr & (if source.len == 0: "" else:
    """<details class="source"><summary></summary><pre><code class="nim-source">""" & source &
    "</code></pre></details>\n") &
  """<div class="foot">Made with <a href="https://github.com/pietroppeter/nimib">nimib</a>.
Blocks marked "nim · ran" were executed when this page was built.
Source: """ & sourceLink & ".</div></footer>" & nanuqScripts

func emptyPartial(blk: JsonNode, nb: Nb): string = ""

proc escapeAttr(s: string): string =
  for c in s:
    case c
    of '&': result.add "&amp;"
    of '"': result.add "&quot;"
    of '<': result.add "&lt;"
    of '>': result.add "&gt;"
    else: result.add c

proc useNanuqTheme*(nb: var Nb, titleHtml, eyebrow, epigraph, meta: string, summary = "",
                    sourcePath = "") =
  ## `titleHtml` may contain `<em>` for the accented word. `summary` becomes the
  ## description meta tag. `sourcePath` (from the repo root) is linked in the footer.
  let description =
    if summary.len > 0: "<meta name=\"description\" content=\"" & escapeAttr(summary) & "\">\n"
    else: ""
  nb.doc.context["stylesheet"] = %(description & nanuqHead)
  nb.doc.context["highlight"] = %""
  nb.doc.context["nb_style"] = %""
  nb.doc.context["disableHighlightJs"] = %true
  nb.doc.context["title_html"] = %titleHtml
  nb.doc.context["eyebrow"] = %eyebrow
  nb.doc.context["epigraph"] = %epigraph
  nb.doc.context["meta"] = %meta
  nb.doc.context["source_path"] = %sourcePath
  nb.backend.partials["header"] = nanuqHeader
  nb.backend.partials["footer"] = nanuqFooter
  nb.backend.partials["left"] = emptyPartial
  nb.backend.partials["right"] = emptyPartial

const
  repoRoot = currentSourcePath.parentDir.parentDir
  builtWith = block:
    ## "Nanuq 0.6.0, Polars 2.1.0", read from the package and the crate.
    var nanuq, polars: string
    for line in staticRead(repoRoot / "nanuq.nimble").splitLines:
      if line.startsWith("version"): nanuq = line.split('"')[1]
    for line in staticRead(repoRoot / "src" / "rust" / "Cargo.toml").splitLines:
      if line.startsWith("polars ="):
        if "tag = \"py-" in line: polars = line.split("tag = \"py-")[1].split('"')[0]
        elif "version = \"" in line: polars = line.split("version = \"")[1].split('"')[0]
    "Nanuq " & nanuq & (if polars.len > 0: ", Polars " & polars else: "")

func longDate(isoDate: string): string =
  ## "2026-11-01" -> "1 November 2026"
  const months = ["January", "February", "March", "April", "May", "June", "July",
                  "August", "September", "October", "November", "December"]
  let parts = isoDate.split('-')
  $parts[2].parseInt & " " & months[parts[1].parseInt - 1] & " " & parts[0]

func postLink(p: DevlogPost): string =
  &"""<a href="{p.fileName}">{p.plainTitle}</a>"""

func devlogNav(i: int): string =
  result = """<nav class="devlog" aria-label="More from the dev log"><div class="pn">"""
  if i > 0:
    let p = devlogPosts[i - 1]
    result.add &"""<a class="prev" rel="prev" href="{p.fileName}"><small>← Previous</small>{p.plainTitle}</a>"""
  if i < devlogPosts.high:
    let p = devlogPosts[i + 1]
    result.add &"""<a class="next" rel="next" href="{p.fileName}"><small>Next →</small>{p.plainTitle}</a>"""
  result.add "</div>"
  var related: seq[string]
  for j in relatedTo(devlogPosts[i].slug):
    if abs(j - i) != 1: related.add postLink(devlogPosts[j])  # prev/next are already linked
  if related.len > 0:
    result.add """<p class="rel"><span>Related:</span> """ & related.join(", ") & "</p>"
  result.add &"""<span class="links"><a href="../index.html">All posts</a> · """ &
    &"""<a href="{sourceUrl}{devlogPosts[i].source}">This post's source on GitHub</a></span></nav>""" & "\n"

proc useDevlogPost*(nb: var Nb, slug, epigraph: string) =
  ## Theme, title, dated file name, eyebrow, meta, summary and footer links of the
  ## dev-log post `slug`, all from its entry in devlog.nim.
  let i = findPost(slug)
  doAssert i >= 0, "devlog: add " & slug & " to docs/devlog.nim"
  let p = devlogPosts[i]
  nb.title = p.plainTitle
  # dated slug (module names can't start with a digit)
  nb.doc.filename = nb.doc.filename.parentDir / p.fileName
  nb.useNanuqTheme(
    titleHtml = p.titleHtml,
    eyebrow = """<a href="../index.html">Nanuq dev log</a> · """ & longDate(p.date),
    epigraph = epigraph,
    meta = &"{p.kind} · Nanuq {p.release} · built with {builtWith} and Nim {NimVersion} · rendered with nimib",
    summary = p.summary,
    sourcePath = p.source,
  )
  nb.doc.context["devlog_nav"] = %devlogNav(i)
