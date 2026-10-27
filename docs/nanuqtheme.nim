## A nimib theme for the Nanuq docs: pack-ice palette, light and dark,
## self-contained apart from Google Fonts and highlight.js for Rust snippets.
##
## Usage, right after `nbInit`:
##   nb.useNanuqTheme(eyebrow = "Nanuq · proof of concept", epigraph = "...")

import std/[json, strformat]
import nimib

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
blockquote { border-left: 3px solid var(--fjord); margin: 1rem 0; padding-left: 1rem; color: var(--mute); }
ul { padding-left: 1.2rem; }
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
  """<footer><div class="foot">Made with <a href="https://github.com/pietroppeter/nimib">nimib</a>.
Blocks marked "nim · ran" were executed when this page was built.
Source: <a href="https://github.com/pietroppeter/nanuq">pietroppeter/nanuq</a>.</div></footer>""" & nanuqScripts

func emptyPartial(blk: JsonNode, nb: Nb): string = ""

proc useNanuqTheme*(nb: var Nb, titleHtml, eyebrow, epigraph, meta: string) =
  ## `titleHtml` may contain `<em>` for the accented word.
  nb.doc.context["stylesheet"] = %nanuqHead
  nb.doc.context["highlight"] = %""
  nb.doc.context["nb_style"] = %""
  nb.doc.context["disableHighlightJs"] = %true
  nb.doc.context["title_html"] = %titleHtml
  nb.doc.context["eyebrow"] = %eyebrow
  nb.doc.context["epigraph"] = %epigraph
  nb.doc.context["meta"] = %meta
  nb.backend.partials["header"] = nanuqHeader
  nb.backend.partials["footer"] = nanuqFooter
  nb.backend.partials["left"] = emptyPartial
  nb.backend.partials["right"] = emptyPartial
