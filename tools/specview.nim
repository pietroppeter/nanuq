## specview: a review page for the OpenSpec changes in this repository.
##
## Reads `openspec/` (changes, archive, main specs), `BACKLOG.md` and, with `--base`,
## git, and writes one self-contained HTML page:
## - where each change is in the process (proposal → specs → design → tasks →
##   implementation → archive),
## - its proposal, design and tasks, and its revisions (each commit that touched it,
##   shown as word diffs of the changed paragraphs),
## - its spec deltas as requirement cards, with MODIFIED requirements shown as a word
##   diff against the current spec,
## - with `--base`, a line diff of every OpenSpec, backlog and changelog file changed
##   since that git ref,
## - every main spec in full (`openspec/specs/`), with its requirements, examples and
##   scenarios, marking the specs that active changes touch.
##
## Archived changes are hidden until "Show archived changes" is ticked, except those
## changed since `--base`.
##
## Usage:
##   nim r tools/specview.nim [--base:origin/main] [--out:specview.html] [--md:summary.md]
##
## Only the standard library is used, so it runs without the Rust build.

import std/[os, osproc, strutils, tables, algorithm, parseopt, sequtils, times]
import experimental/diff

# ---------------------------------------------------------------------------
# Model and parsing
# ---------------------------------------------------------------------------

type
  Scenario = object
    name: string
    lines: seq[string]

  Requirement = object
    name: string
    body: string
    scenarios: seq[Scenario]

  Section = object
    title: string           ## "Requirements", "ADDED Requirements", ...
    reqs: seq[Requirement]

  SpecDoc = object
    purpose: string
    sections: seq[Section]

  Task = object
    id, text: string
    done: bool

  TaskGroup = object
    title: string
    tasks: seq[Task]

  CapDelta = object
    name: string
    delta: SpecDoc
    current: SpecDoc
    isNew: bool

  Change = object
    name, dir: string
    archived: bool
    created: string
    proposal, design: string
    hasProposal, hasDesign, hasTasks: bool
    tasks: seq[TaskGroup]
    caps: seq[CapDelta]
    backlog: seq[string]    ## titles of BACKLOG.md entries naming this change
    touched: bool           ## changed since --base

proc readOr(path: string, default = ""): string =
  if fileExists(path): readFile(path) else: default

proc parseSpec(text: string): SpecDoc =
  var section = -1
  var inPurpose = false
  var purpose: seq[string]
  template curReq: untyped = result.sections[section].reqs[^1]
  var inFence = false
  for raw in text.splitLines:
    let line = raw.strip(leading = false)
    if line.strip.startsWith("```"): inFence = not inFence
    if inFence or line.strip.startsWith("```"):
      # code examples: kept verbatim, never read as headings
      if section >= 0 and result.sections[section].reqs.len > 0 and curReq.scenarios.len == 0:
        curReq.body.add line & "\n"
      elif inPurpose: purpose.add line
    elif line.startsWith("## "):
      let title = line[3..^1].strip
      inPurpose = title == "Purpose"
      if not inPurpose:
        result.sections.add Section(title: title)
        section = result.sections.high
    elif line.startsWith("### Requirement:"):
      if section < 0:
        result.sections.add Section(title: "Requirements")
        section = 0
      result.sections[section].reqs.add Requirement(name: line["### Requirement:".len..^1].strip)
    elif line.startsWith("#### Scenario:"):
      if section >= 0 and result.sections[section].reqs.len > 0:
        curReq.scenarios.add Scenario(name: line["#### Scenario:".len..^1].strip)
    elif line.startsWith("# "):
      discard
    elif inPurpose:
      purpose.add line
    elif section >= 0 and result.sections[section].reqs.len > 0:
      if curReq.scenarios.len > 0:
        if line.len > 0: curReq.scenarios[^1].lines.add line
      else:
        curReq.body.add line & "\n"
  result.purpose = purpose.join("\n").strip
  for s in result.sections.mitems:
    for r in s.reqs.mitems: r.body = r.body.strip

proc parseTasks(text: string): seq[TaskGroup] =
  for raw in text.splitLines:
    let line = raw.strip
    if line.startsWith("## "):
      result.add TaskGroup(title: line[3..^1].strip)
    elif line.startsWith("- [") and line.len > 4:
      let close = line.find(']')
      if close < 0: continue
      if result.len == 0: result.add TaskGroup(title: "Tasks")
      let mark = line[3 ..< close].strip
      var rest = line[close + 1 .. ^1].strip
      var id = ""
      let sp = rest.find(' ')
      if sp > 0 and rest[0].isDigit:
        id = rest[0 ..< sp]
        rest = rest[sp + 1 .. ^1]
      result[^1].tasks.add Task(id: id, text: rest, done: mark.toLowerAscii == "x")

proc sectionsOf(md: string): OrderedTable[string, string] =
  var cur = ""
  for line in md.splitLines:
    if line.startsWith("## "):
      cur = line[3..^1].strip
      result[cur] = ""
    elif cur.len > 0:
      result[cur].add line & "\n"

proc backlogEntries(backlog: string): seq[(string, string)] =
  ## (title, full text) of every top-level "- **Title**" entry.
  var title, body: string
  for line in backlog.splitLines:
    if line.startsWith("- **") or line.startsWith("## "):
      if title.len > 0: result.add (title, body)
      title = ""; body = ""
      if line.startsWith("- **"):
        let e = line.find("**", 4)
        title = if e > 4: line[4 ..< e] else: line
    if title.len > 0: body.add line & "\n"
  if title.len > 0: result.add (title, body)

proc loadChange(root, dir: string, archived: bool, backlog: seq[(string, string)]): Change =
  result.dir = dir.relativePath(root).replace('\\', '/')
  result.archived = archived
  result.name = dir.lastPathPart
  if archived and result.name.len > 11 and result.name[10] == '-':
    result.name = result.name[11..^1]   # archive dirs are prefixed with a date
  for line in readOr(dir / ".openspec.yaml").splitLines:
    if line.startsWith("created:"): result.created = line[8..^1].strip
  result.proposal = readOr(dir / "proposal.md")
  result.design = readOr(dir / "design.md")
  result.hasProposal = result.proposal.len > 0
  result.hasDesign = result.design.len > 0
  result.hasTasks = fileExists(dir / "tasks.md")
  result.tasks = parseTasks(readOr(dir / "tasks.md"))
  if dirExists(dir / "specs"):
    for f in walkDirRec(dir / "specs"):
      if f.endsWith("spec.md"):
        let cap = f.parentDir.relativePath(dir / "specs")
        let mainPath = root / "openspec" / "specs" / cap / "spec.md"
        result.caps.add CapDelta(name: cap, delta: parseSpec(readFile(f)),
                                 current: parseSpec(readOr(mainPath)),
                                 isNew: not fileExists(mainPath))
  result.caps.sort(proc (a, b: CapDelta): int = cmp(a.name, b.name))
  for (title, body) in backlog:
    if result.name in body: result.backlog.add title

proc taskCounts(c: Change): (int, int) =
  for g in c.tasks:
    for t in g.tasks:
      inc result[1]
      if t.done: inc result[0]

proc stage(c: Change): string =
  let (done, total) = c.taskCounts
  if c.archived: "Archived"
  elif not (c.hasProposal and c.caps.len > 0 and c.hasTasks): "Planning"
  elif done == 0: "Ready to apply"
  elif done < total: "Implementing"
  else: "Ready to archive"

# ---------------------------------------------------------------------------
# HTML helpers: escaping, a small Markdown subset, word and line diffs
# ---------------------------------------------------------------------------

proc esc(s: string): string =
  result = newStringOfCap(s.len)
  for ch in s:
    case ch
    of '&': result.add "&amp;"
    of '<': result.add "&lt;"
    of '>': result.add "&gt;"
    of '"': result.add "&quot;"
    else: result.add ch

proc inline(s: string): string =
  ## `code`, **bold**, *em*, [text](url); everything else escaped.
  var i = 0
  while i < s.len:
    if s[i] == '`':
      let e = s.find('`', i + 1)
      if e > i:
        result.add "<code>" & esc(s[i+1 ..< e]) & "</code>"; i = e + 1; continue
    elif s[i] == '*' and i + 1 < s.len and s[i+1] == '*':
      let e = s.find("**", i + 2)
      if e > i:
        result.add "<strong>" & inline(s[i+2 ..< e]) & "</strong>"; i = e + 2; continue
    elif s[i] == '*' and i + 1 < s.len and s[i+1] != ' ':
      let e = s.find('*', i + 1)
      if e > i + 1:
        result.add "<em>" & inline(s[i+1 ..< e]) & "</em>"; i = e + 1; continue
    elif s[i] == '[':
      let m = s.find("](", i)
      let e = if m > 0: s.find(')', m) else: -1
      if m > i and e > m and '\n' notin s[i..e]:
        result.add "<a href=\"" & esc(s[m+2 ..< e]) & "\">" & inline(s[i+1 ..< m]) & "</a>"
        i = e + 1; continue
    result.add esc($s[i])
    inc i

proc md(text: string): string =
  ## Headings, paragraphs, bullet/numbered lists (one level), fenced code.
  var para: seq[string]
  var list: seq[string]
  var listTag = ""
  var code: seq[string]
  var inCode = false
  var lang = ""
  template flushPara() =
    if para.len > 0: result.add "<p>" & inline(para.join(" ")) & "</p>\n"; para = @[]
  template flushList() =
    if list.len > 0:
      result.add "<" & listTag & ">"
      for it in list: result.add "<li>" & inline(it) & "</li>"
      result.add "</" & listTag & ">\n"
      list = @[]
  for raw in text.splitLines:
    let line = raw.strip(leading = false)
    let s = line.strip
    if s.startsWith("```"):
      if inCode:
        # a ```text block shows an example's output
        let cls = if lang == "text": " class=\"out\"" else: ""
        result.add "<pre" & cls & "><code>" & esc(code.join("\n")) & "</code></pre>\n"; code = @[]
      else:
        flushPara(); flushList()
        lang = s[3..^1].strip
      inCode = not inCode
    elif inCode: code.add raw
    elif s.startsWith("<!--"): discard
    elif s.len == 0: flushPara(); flushList()
    elif s.startsWith("#"):
      flushPara(); flushList()
      let level = min(s.len - s.strip(chars = {'#'}).len + 2, 6)
      result.add "<h" & $level & ">" & inline(s.strip(chars = {'#', ' '})) & "</h" & $level & ">\n"
    elif s.startsWith("- ") or s.startsWith("* ") or
         (s.len > 2 and s[0].isDigit and (s.find(". ") in 1..3)):
      flushPara()
      let ordered = s[0].isDigit
      let tag = if ordered: "ol" else: "ul"
      if list.len > 0 and tag != listTag: flushList()
      listTag = tag
      list.add(if ordered: s[s.find(". ") + 2 .. ^1] else: s[2..^1])
    elif list.len > 0 and raw.startsWith(" "): list[^1].add " " & s
    else: para.add s
  flushPara(); flushList()

proc tokens(s: string): seq[string] =
  ## Words and whitespace runs, so a diff can be rejoined exactly.
  var cur = ""
  for ch in s:
    if cur.len > 0 and (ch in Whitespace) != (cur[^1] in Whitespace):
      result.add cur; cur = ""
    cur.add ch
  if cur.len > 0: result.add cur

proc wordDiff(a, b: string): string =
  let ta = tokens(a)
  let tb = tokens(b)
  var ids: Table[string, int]
  proc idsOf(ts: seq[string]): seq[int] =
    for t in ts: result.add ids.mgetOrPut(t, ids.len)
  let items = diffInt(idsOf(ta), idsOf(tb))
  var ia, ib = 0
  for it in items:
    while ia < it.startA: result.add esc(ta[ia]); inc ia; inc ib
    if it.deletedA > 0: result.add "<del>" & esc(ta[it.startA ..< it.startA + it.deletedA].join) & "</del>"
    if it.insertedB > 0: result.add "<ins>" & esc(tb[it.startB ..< it.startB + it.insertedB].join) & "</ins>"
    ia = it.startA + it.deletedA
    ib = it.startB + it.insertedB
  while ia < ta.len: result.add esc(ta[ia]); inc ia

proc reqText(r: Requirement): string =
  result = r.body
  for s in r.scenarios:
    result.add "\n\nScenario: " & s.name
    for l in s.lines: result.add "\n" & l

proc lineDiff(a, b: string, context = 3): (string, int, int) =
  ## Unified diff rendered as table rows, plus added and removed line counts.
  let la = if a.len == 0: @[] else: a.splitLines
  let lb = if b.len == 0: @[] else: b.splitLines
  let items = diffText(la.join("\n"), lb.join("\n"))
  var rows = ""
  var added, removed = 0
  proc row(kind, na, nb, text: string): string =
    "<tr class=\"" & kind & "\"><td class=\"ln\">" & na & "</td><td class=\"ln\">" & nb &
      "</td><td class=\"tx\">" & esc(text) & "</td></tr>\n"
  var ia = 0
  var ib = 0
  var lastShown = -1
  for idx, it in items:
    let from0 = max(ia, it.startA - context)
    if from0 > lastShown + 1 and lastShown >= 0 or (lastShown < 0 and from0 > 0):
      rows.add "<tr class=\"gap\"><td class=\"ln\"></td><td class=\"ln\"></td><td class=\"tx\">⋯</td></tr>\n"
    ib += from0 - ia
    ia = from0
    while ia < it.startA:
      rows.add row("eq", $(ia + 1), $(ib + 1), la[ia]); inc ia; inc ib
    for k in 0 ..< it.deletedA:
      rows.add row("rm", $(it.startA + k + 1), "", la[it.startA + k]); inc removed
    for k in 0 ..< it.insertedB:
      rows.add row("ad", "", $(it.startB + k + 1), lb[it.startB + k]); inc added
    ia = it.startA + it.deletedA
    ib = it.startB + it.insertedB
    let nextStart = if idx < items.high: items[idx + 1].startA else: la.len
    let upto = min(ia + context, nextStart)
    while ia < upto:
      rows.add row("eq", $(ia + 1), $(ib + 1), la[ia]); inc ia; inc ib
    lastShown = ia - 1
  if lastShown >= 0 and lastShown < la.len - 1:
    rows.add "<tr class=\"gap\"><td class=\"ln\"></td><td class=\"ln\"></td><td class=\"tx\">⋯</td></tr>\n"
  (rows, added, removed)

# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------

const css = """
:root{--ice:#f3f7f9;--floe:#fff;--ink:#12222e;--mute:#5a6b77;--rule:#d5e1e8;--fjord:#0d6f86;
--add:#e3f4e6;--add-ink:#1f6b2c;--del:#fbe7e4;--del-ink:#a2321f;--mod:#fff2d6;--mod-ink:#8a5a00;
--display:"Familjen Grotesk","Helvetica Neue",Arial,sans-serif;--body:"Literata",Georgia,serif;
--mono:"JetBrains Mono",ui-monospace,Menlo,Consolas,monospace;color-scheme:light}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--ice:#0d161d;--floe:#121e27;
--ink:#e3ecf1;--mute:#93a6b3;--rule:#22323e;--fjord:#5cc4dc;--add:#12301b;--add-ink:#8fd19a;
--del:#3a1a16;--del-ink:#f0a092;--mod:#33290f;--mod-ink:#f0c868;color-scheme:dark}}
*{box-sizing:border-box}
body{margin:0;background:var(--ice);color:var(--ink);font:16px/1.6 var(--body);
padding:0 max(16px,env(safe-area-inset-left,0px))}
main,header.mast{max-width:62rem;margin:0 auto}
header.mast{padding:2.5rem 0 1.5rem;border-bottom:1px solid var(--rule)}
.eyebrow{font:600 .75rem/1 var(--mono);letter-spacing:.12em;text-transform:uppercase;color:var(--fjord)}
h1{font:700 clamp(2rem,6vw,3rem)/1.05 var(--display);margin:.5rem 0}
h2,h3,h4,h5{font-family:var(--display);line-height:1.2}
h2{font-size:1.6rem;margin:2.5rem 0 .5rem}
h3{font-size:1.2rem;margin:1.6rem 0 .4rem}
.meta{font:.8rem/1.4 var(--mono);color:var(--mute)}
a{color:var(--fjord)}
code,pre{font-family:var(--mono);font-size:.85em}
p code,li code,td code{background:var(--rule);padding:.05em .3em;border-radius:3px}
pre{background:var(--floe);border:1px solid var(--rule);border-radius:6px;padding:.8rem;overflow-x:auto;line-height:1.25}
pre + pre.out{margin-top:-.4rem;border-top-left-radius:0;border-top-right-radius:0}
pre.out{background:var(--ice);border-style:dashed;position:relative}
pre.out::before{content:"output";position:absolute;top:.3rem;right:.6rem;font-size:.7rem;color:var(--mute);font-family:var(--display)}
table.overview{border-collapse:collapse;width:100%;font-size:.9rem;margin:1rem 0}
table.overview th,table.overview td{text-align:left;padding:.4rem .6rem;border-bottom:1px solid var(--rule);vertical-align:top}
table.overview th{font:600 .7rem/1 var(--mono);text-transform:uppercase;letter-spacing:.08em;color:var(--mute)}
.change{background:var(--floe);border:1px solid var(--rule);border-radius:10px;padding:1.2rem 1.4rem;margin:1.5rem 0}
.change>h2{margin-top:0}
.pill{display:inline-block;font:600 .7rem/1 var(--mono);letter-spacing:.06em;text-transform:uppercase;
padding:.35rem .55rem;border-radius:99px;border:1px solid var(--rule);color:var(--mute);vertical-align:middle;white-space:nowrap}
.pill.stage{background:var(--fjord);color:var(--floe);border-color:var(--fjord)}
.pill.touched{color:var(--mod-ink);background:var(--mod);border-color:transparent}
.steps{display:flex;flex-wrap:wrap;gap:.3rem;margin:1rem 0;padding:0;list-style:none}
.steps li{font:600 .72rem/1 var(--mono);padding:.5rem .7rem;border-radius:6px;border:1px solid var(--rule);color:var(--mute)}
.steps li.done{background:var(--add);color:var(--add-ink);border-color:transparent}
.steps li.now{background:var(--fjord);color:var(--floe);border-color:var(--fjord)}
.steps li.skip{border-style:dashed}
.bar{height:6px;background:var(--rule);border-radius:3px;overflow:hidden;margin:.3rem 0 .8rem}
.bar>span{display:block;height:100%;background:var(--fjord)}
details{border-top:1px solid var(--rule);padding:.5rem 0}
details>summary{cursor:pointer;font:700 1.05rem/1.4 var(--display);list-style-position:outside}
details>summary .meta{font-weight:400;margin-left:.5rem}
.cap{margin:1rem 0 1.5rem}
.cap>h4{margin:0 0 .5rem;font-size:1.05rem}
.req{border:1px solid var(--rule);border-left:4px solid var(--rule);border-radius:6px;padding:.7rem 1rem;margin:.6rem 0;background:var(--ice)}
.req.ADDED{border-left-color:var(--add-ink)}.req.MODIFIED{border-left-color:var(--mod-ink)}
.req.REMOVED{border-left-color:var(--del-ink)}.req.RENAMED{border-left-color:var(--fjord)}
.req .op{font:700 .65rem/1 var(--mono);letter-spacing:.08em;margin-right:.5rem}
.ADDED .op{color:var(--add-ink)}.MODIFIED .op{color:var(--mod-ink)}.REMOVED .op{color:var(--del-ink)}
.req h5{display:inline;font-size:1rem;margin:0}
.req p{margin:.4rem 0}
.scn{margin:.5rem 0 0;padding:.5rem .8rem;border-radius:4px;background:var(--floe);font-size:.92rem}
.scn b{font-family:var(--display)}
.scn ul{margin:.2rem 0;padding-left:1.1rem}
.wdiff{white-space:pre-wrap;font-size:.92rem;margin:.4rem 0}
ins{background:var(--add);color:var(--add-ink);text-decoration:none}
del{background:var(--del);color:var(--del-ink)}
.unchanged{color:var(--mute);font-size:.9rem}
.tasks{list-style:none;padding:0;margin:.3rem 0 1rem}
.tasks li{padding:.15rem 0 .15rem 1.7rem;position:relative}
.tasks li::before{content:"○";position:absolute;left:.3rem;color:var(--mute)}
.tasks li.done::before{content:"✓";color:var(--add-ink);font-weight:700}
.tasks li.done{color:var(--mute)}
.tid{font:.75rem var(--mono);color:var(--mute);margin-right:.3rem}
table.diff{border-collapse:collapse;width:100%;font:.78rem/1.45 var(--mono);background:var(--floe)}
table.diff td{padding:0 .5rem;vertical-align:top}
table.diff td.ln{color:var(--mute);text-align:right;width:3rem;user-select:none;border-right:1px solid var(--rule)}
table.diff td.tx{white-space:pre-wrap;word-break:break-word}
tr.ad{background:var(--add)}tr.ad td.tx::before{content:"+ ";color:var(--add-ink)}
tr.rm{background:var(--del)}tr.rm td.tx::before{content:"− ";color:var(--del-ink)}
tr.eq td.tx::before{content:"  "}
tr.gap td{color:var(--mute);text-align:center}
.diffwrap{overflow-x:auto;border:1px solid var(--rule);border-radius:6px;margin:.5rem 0}
.count .a{color:var(--add-ink)}.count .r{color:var(--del-ink)}
.rev{margin:.8rem 0 1.2rem}
.revhead{margin-bottom:.4rem}
.revfile{margin:.6rem 0 .2rem;font-size:.9rem}
.hunk{border:1px solid var(--rule);border-radius:6px;padding:.5rem .8rem;margin:.4rem 0;background:var(--ice)}
.where{font:600 .7rem/1.2 var(--mono);color:var(--mute);text-transform:uppercase;letter-spacing:.06em;margin-bottom:.2rem}
.nav{display:flex;flex-wrap:wrap;gap:1rem;align-items:center;margin:1rem 0 0;font:600 .8rem/1 var(--mono)}
.nav label{color:var(--mute);cursor:pointer;display:inline-flex;gap:.4rem;align-items:center}
body:not(.show-archived) .archived{display:none}
.hint{font:.8rem/1.4 var(--mono);color:var(--mute)}
.spec{background:var(--floe);border:1px solid var(--rule);border-radius:10px;padding:.6rem 1.4rem;margin:.8rem 0}
.spec>summary{font-size:1.15rem}
.req.CURRENT{border-left-color:var(--fjord)}
.speclist{columns:2 16rem;font-size:.9rem;padding-left:1.1rem}
footer{max-width:62rem;margin:3rem auto;color:var(--mute);font:.8rem var(--mono)}
"""

const toggleJs = """<script>
(function(){
  var box = document.getElementById("show-archived"), key = "specview-show-archived";
  function apply(on){ document.body.classList.toggle("show-archived", on); box.checked = on; }
  var saved = false;
  try { saved = localStorage.getItem(key) === "1"; } catch(e) {}
  apply(saved);
  box.addEventListener("change", function(){
    apply(box.checked);
    try { localStorage.setItem(key, box.checked ? "1" : "0"); } catch(e) {}
  });
  // a link to an archived change or a spec opens it
  function reveal(){
    var id = decodeURIComponent(location.hash.slice(1)); if (!id) return;
    var el = document.getElementById(id); if (!el) return;
    if (el.classList.contains("archived")) apply(true);
    if (el.tagName === "DETAILS") el.open = true;
    el.scrollIntoView();
  }
  window.addEventListener("hashchange", reveal); reveal();
})();
</script>"""

proc deltaCounts(c: CapDelta): Table[string, int] =
  for s in c.delta.sections:
    result[s.title.split(' ')[0]] = result.getOrDefault(s.title.split(' ')[0]) + s.reqs.len

proc countsLabel(c: CapDelta): string =
  var parts: seq[string]
  let t = c.deltaCounts
  for (k, sym) in [("ADDED", "+"), ("MODIFIED", "~"), ("REMOVED", "−"), ("RENAMED", "→")]:
    if t.getOrDefault(k) > 0: parts.add sym & $t[k]
  parts.join(" ")

proc renderScenarios(r: Requirement): string =
  for s in r.scenarios:
    result.add "<div class=\"scn\"><b>Scenario: " & inline(s.name) & "</b><ul>"
    for l in s.lines:
      result.add "<li>" & inline(l.strip(chars = {'-', ' '})) & "</li>"
    result.add "</ul></div>"

proc renderReq(op: string, r: Requirement, current: SpecDoc): string =
  result.add "<div class=\"req " & op & "\">" &
    (if op == "CURRENT": "" else: "<span class=\"op\">" & op & "</span>") & "<h5>" &
    inline(r.name) & "</h5>"
  if op == "MODIFIED":
    var before: Requirement
    var found = false
    for s in current.sections:
      for cr in s.reqs:
        if cr.name.toLowerAscii.strip == r.name.toLowerAscii.strip:
          before = cr; found = true
    if found:
      result.add "<div class=\"wdiff\">" & wordDiff(reqText(before), reqText(r)) & "</div>"
    else:
      result.add "<p class=\"unchanged\">⚠ No requirement with this name in the current spec, so archiving will fail.</p>" &
        md(r.body) & renderScenarios(r)
  else:
    result.add md(r.body) & renderScenarios(r)
  result.add "</div>\n"

proc renderCap(c: CapDelta): string =
  result.add "<div class=\"cap\"><h4><code>" & esc(c.name) & "</code> " &
    (if c.isNew: "<span class=\"pill touched\">new capability</span>" else: "<span class=\"pill\">modified</span>") &
    " <span class=\"meta\">" & c.countsLabel & "</span></h4>"
  if c.delta.purpose.len > 0: result.add "<p><em>Purpose:</em> " & inline(c.delta.purpose) & "</p>"
  var changed: seq[string]
  for s in c.delta.sections:
    let op = s.title.split(' ')[0]
    for r in s.reqs:
      changed.add r.name.toLowerAscii
      result.add renderReq(op, r, c.current)
  if not c.isNew:
    var same: seq[string]
    for s in c.current.sections:
      for r in s.reqs:
        if r.name.toLowerAscii notin changed: same.add r.name
    if same.len > 0:
      result.add "<p class=\"unchanged\">Unchanged in this spec: " & same.mapIt(inline(it)).join(", ") & "</p>"
  result.add "</div>"

proc renderSteps(c: Change): string =
  let (done, total) = c.taskCounts
  type St = tuple[label, cls: string]
  let implCls = if c.archived or (total > 0 and done == total): "done"
                elif done > 0: "now" else: ""
  var steps: seq[St] = @[
    ("Proposal", if c.hasProposal: "done" else: "now"),
    ("Specs", if c.caps.len > 0: "done" elif c.hasProposal: "now" else: ""),
    ("Design", if c.hasDesign: "done" elif c.hasTasks: "skip" else: ""),
    ("Tasks", if c.hasTasks: "done" elif c.caps.len > 0: "now" else: ""),
    ("Implement " & $done & "/" & $total, implCls),
    ("Archive", if c.archived: "done" elif total > 0 and done == total: "now" else: "")]
  if c.hasProposal and c.caps.len > 0 and c.hasTasks and done == 0 and not c.archived:
    steps[4].cls = "now"
  result = "<ol class=\"steps\">"
  for s in steps: result.add "<li class=\"" & s.cls & "\">" & esc(s.label) & "</li>"
  result.add "</ol>"

proc git(root: string, args: varargs[string]): (string, int) =
  execCmdEx("git -C " & quoteShell(root) & " " & args.mapIt(quoteShell(it)).join(" "))

proc paragraphs(text: string): seq[string] =
  for p in text.replace("\r\n", "\n").split("\n\n"):
    if p.strip.len > 0: result.add p.strip(chars = {'\n'})

proc paraDiff(a, b: string): string =
  ## Changed paragraphs only, each as a word diff, labelled with the nearest heading.
  let pa = paragraphs(a)
  let pb = paragraphs(b)
  var ids: Table[string, int]
  proc idsOf(ps: seq[string]): seq[int] =
    for p in ps: result.add ids.mgetOrPut(p, ids.len)
  for it in diffInt(idsOf(pa), idsOf(pb)):
    var where = ""
    let first = if it.startB < pb.len and pb[it.startB].startsWith("#"): it.startB else: it.startB - 1
    for k in countdown(min(first, pb.high), 0):
      if pb[k].startsWith("#"):
        where = pb[k].strip(chars = {'#', ' '}).splitLines[0]; break
    let before = pa[it.startA ..< it.startA + it.deletedA].join("\n\n")
    let after = pb[it.startB ..< it.startB + it.insertedB].join("\n\n")
    result.add "<div class=\"hunk\">" &
      (if where.len > 0: "<div class=\"where\">§ " & esc(where) & "</div>" else: "") &
      "<div class=\"wdiff\">" & wordDiff(before, after) & "</div></div>"

type Revision = object
  label, sha, date, subject: string

proc revisions(root, dir: string): seq[Revision] =
  let (log, code) = git(root, "log", "--reverse", "--format=%h%x09%ad%x09%s", "--date=short", "--", dir)
  if code != 0: return
  for line in log.splitLines:
    let f = line.split('\t', 2)
    if f.len == 3: result.add Revision(sha: f[0], date: f[1], subject: f[2])
  let (dirty, _) = git(root, "status", "--porcelain", "--", dir)
  if dirty.strip.len > 0:
    result.add Revision(sha: "", date: "", subject: "uncommitted changes in the working tree")
  for i, r in result.mpairs: r.label = "r" & $(i + 1)

proc fileAt(root, sha, path: string): string =
  if sha.len == 0: return readOr(root / path)
  let (s, code) = git(root, "show", sha & ":" & path)
  if code == 0: s else: ""

proc renderRevisions(root: string, c: Change): string =
  let revs = revisions(root, c.dir)
  if revs.len == 0: return
  result.add "<details" & (if revs.len > 1: " open" else: "") & "><summary>Revisions<span class=\"meta\">" &
    $revs.len & (if revs.len == 1: " revision" else: " revisions") & "</span></summary>"
  for i, r in revs:
    result.add "<div class=\"rev\"><div class=\"revhead\"><span class=\"pill stage\">" & r.label &
      "</span> <code>" & esc(if r.sha.len > 0: r.sha else: "working tree") & "</code> <span class=\"meta\">" &
      esc(r.date) & "</span> " & inline(r.subject) & "</div>"
    if i == 0:
      let (files, _) = git(root, "ls-tree", "-r", "--name-only", (if r.sha.len > 0: r.sha else: "HEAD"), "--", c.dir)
      let names = files.splitLines.filterIt(it.len > 0).mapIt(it.relativePath(c.dir))
      result.add "<p class=\"unchanged\">First version: " & names.mapIt("<code>" & esc(it) & "</code>").join(", ") & "</p>"
    else:
      let prev = revs[i - 1].sha
      let (files, _) = if r.sha.len > 0: git(root, "diff", "--name-only", prev, r.sha, "--", c.dir)
                       else: git(root, "diff", "--name-only", prev, "--", c.dir)
      for f in files.splitLines:
        if f.strip.len == 0: continue
        result.add "<div class=\"revfile\"><code>" & esc(f.relativePath(c.dir)) & "</code></div>" &
          paraDiff(fileAt(root, prev, f), fileAt(root, r.sha, f))
    result.add "</div>"
  result.add "</details>"

proc renderChange(c: Change, root: string): string =
  let (done, total) = c.taskCounts
  let hidden = c.archived and not c.touched
  result.add "<section class=\"change" & (if hidden: " archived" else: "") & "\" id=\"" &
    esc(c.name) & "\"><h2>" & esc(c.name) &
    " <span class=\"pill stage\">" & c.stage & "</span>" &
    (if c.touched: " <span class=\"pill touched\">changed in this diff</span>" else: "") & "</h2>"
  result.add "<div class=\"meta\">" & (if c.created.len > 0: "created " & esc(c.created) & " · " else: "") &
    esc(c.dir) & "</div>"
  result.add renderSteps(c)
  if c.backlog.len > 0:
    result.add "<p><strong>From the backlog:</strong> " & c.backlog.mapIt(inline(it)).join("; ") & "</p>"
  let ps = sectionsOf(c.proposal)
  if c.hasProposal:
    result.add "<details open><summary>Proposal</summary>"
    for key in ["Why", "What Changes"]:
      if key in ps: result.add "<h3>" & key & "</h3>" & md(ps[key])
    for key, val in ps:
      if key notin ["Why", "What Changes"]: result.add "<h3>" & esc(key) & "</h3>" & md(val)
    result.add "</details>"
  if c.caps.len > 0:
    result.add "<details open><summary>Spec changes<span class=\"meta\">" &
      c.caps.mapIt(esc(it.name) & " " & it.countsLabel).join(" · ") & "</span></summary>"
    for cap in c.caps: result.add renderCap(cap)
    result.add "</details>"
  if c.hasDesign:
    result.add "<details><summary>Design</summary>" & md(c.design) & "</details>"
  if c.hasTasks:
    result.add "<details " & (if done > 0 and done < total: "open" else: "") &
      "><summary>Tasks<span class=\"meta\">" & $done & " of " & $total & " done</span></summary>"
    for g in c.tasks:
      let gd = g.tasks.countIt(it.done)
      result.add "<h4>" & inline(g.title) & " <span class=\"meta\">" & $gd & "/" & $g.tasks.len & "</span></h4>"
      if g.tasks.len > 0:
        result.add "<div class=\"bar\"><span style=\"width:" & $(gd * 100 div g.tasks.len) & "%\"></span></div>"
      result.add "<ul class=\"tasks\">"
      for t in g.tasks:
        result.add "<li class=\"" & (if t.done: "done" else: "") & "\"><span class=\"tid\">" & esc(t.id) &
          "</span>" & inline(t.text) & "</li>"
      result.add "</ul>"
    result.add "</details>"
  result.add renderRevisions(root, c)
  result.add "</section>\n"


proc changedFiles(root, base: string): seq[string] =
  let scope = ["openspec", "BACKLOG.md", "CHANGELOG.md"]
  let (tracked, code) = git(root, @["diff", "--name-only", base, "--"] & @scope)
  if code != 0: quit "git diff against " & base & " failed:\n" & tracked
  let (untracked, _) = git(root, @["ls-files", "--others", "--exclude-standard", "--"] & @scope)
  for l in (tracked & "\n" & untracked).splitLines:
    if l.strip.len > 0 and l.strip notin result: result.add l.strip
  result.sort

proc renderRawDiff(root, base: string, files: seq[string]): string =
  result.add "<h2 id=\"raw-diff\">Files changed since <code>" & esc(base) & "</code></h2>"
  if files.len == 0:
    return result & "<p class=\"unchanged\">No OpenSpec, backlog or changelog files changed.</p>"
  for f in files:
    let (old, code) = git(root, "show", base & ":" & f)
    let before = if code == 0: old else: ""
    let after = readOr(root / f)
    let (rows, added, removed) = lineDiff(before, after)
    let tag = if code != 0: " <span class=\"pill touched\">new</span>"
              elif not fileExists(root / f): " <span class=\"pill\">deleted</span>" else: ""
    result.add "<details><summary><code>" & esc(f) & "</code>" & tag &
      "<span class=\"meta count\"><span class=\"a\">+" & $added & "</span> <span class=\"r\">−" & $removed &
      "</span></span></summary><div class=\"diffwrap\"><table class=\"diff\">" & rows & "</table></div></details>"

proc renderMarkdown(changes: seq[Change], base: string, files: seq[string]): string =
  result = "## OpenSpec review\n\n"
  let active = changes.filterIt(not it.archived)
  if active.len == 0: result.add "No active changes.\n"
  else:
    result.add "| Change | Stage | Tasks | Specs |\n|---|---|---|---|\n"
    for c in active:
      let (done, total) = c.taskCounts
      result.add "| " & (if c.touched: "**" & c.name & "**" else: c.name) & " | " & c.stage & " | " &
        $done & "/" & $total & " | " &
        c.caps.mapIt("`" & it.name & "` " & (if it.isNew: "(new) " else: "") & it.countsLabel).join(", ") & " |\n"
  if base.len > 0:
    result.add "\n" & $files.len & " OpenSpec/backlog/changelog files changed since `" & base & "`.\n"
  result.add "\nThe full report (proposal, spec diffs, tasks, file diffs) is in this run's `specview` artifact.\n"

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

proc renderSpecs(root: string, changes: seq[Change], files: seq[string]): string =
  ## Every main spec in full; specs touched by an active change, or changed since
  ## --base, are marked.
  var names: seq[string]
  for kind, dir in walkDir(root / "openspec" / "specs"):
    if kind == pcDir and fileExists(dir / "spec.md"): names.add dir.lastPathPart
  names.sort
  var pending = initTable[string, seq[string]]()
  for c in changes:
    if not c.archived:
      for cap in c.caps: pending.mgetOrPut(cap.name, @[]).add c.name
  result.add "<h2 id=\"specs\">Specs</h2><p class=\"hint\">The current specs in " &
    "openspec/specs, as archived changes left them. Changes still open are not applied here.</p>"
  result.add "<ul class=\"speclist\">"
  for n in names:
    result.add "<li><a href=\"#spec-" & esc(n) & "\"><code>" & esc(n) & "</code></a>" &
      (if n in pending: " <span class=\"pill touched\">open change</span>" else: "") & "</li>"
  result.add "</ul>"
  for n in names:
    let path = "openspec/specs/" & n & "/spec.md"
    let doc = parseSpec(readFile(root / path))
    var nreq = 0
    for sec in doc.sections: nreq += sec.reqs.len
    result.add "<details class=\"spec\" id=\"spec-" & esc(n) & "\"><summary><code>" & esc(n) &
      "</code><span class=\"meta\">" & $nreq & " requirements" &
      (if path in files: " · changed in this diff" else: "") &
      (if n in pending: " · open change: " & pending[n].mapIt(esc(it)).join(", ") else: "") &
      "</span></summary>"
    if doc.purpose.len > 0: result.add "<p><em>Purpose:</em> " & inline(doc.purpose) & "</p>"
    for sec in doc.sections:
      for r in sec.reqs: result.add renderReq("CURRENT", r, doc)
    result.add "</details>\n"

proc main() =
  var root = getCurrentDir()
  var base, outPath, mdPath = ""
  outPath = "specview.html"
  for kind, key, val in getopt():
    case kind
    of cmdLongOption, cmdShortOption:
      case key
      of "base": base = val
      of "out": outPath = val
      of "md": mdPath = val
      of "root": root = val
      of "help", "h":
        echo "usage: specview [--root:DIR] [--base:GIT_REF] [--out:FILE.html] [--md:FILE.md]"; quit 0
      else: quit "unknown option --" & key
    else: discard
  root = root.absolutePath
  if not dirExists(root / "openspec"): quit "no openspec/ directory in " & root

  let backlog = backlogEntries(readOr(root / "BACKLOG.md"))
  var changes: seq[Change]
  for kind, dir in walkDir(root / "openspec" / "changes"):
    if kind == pcDir and dir.lastPathPart != "archive":
      changes.add loadChange(root, dir, false, backlog)
  if dirExists(root / "openspec" / "changes" / "archive"):
    for kind, dir in walkDir(root / "openspec" / "changes" / "archive"):
      if kind == pcDir: changes.add loadChange(root, dir, true, backlog)
  var files: seq[string]
  if base.len > 0:
    files = changedFiles(root, base)
    for c in changes.mitems:
      c.touched = files.anyIt(it.startsWith(c.dir & "/"))
  changes.sort(proc (a, b: Change): int =
    result = cmp(a.archived, b.archived)
    if result == 0: result = cmp(b.touched, a.touched)
    if result == 0: result = cmp(a.name, b.name))

  var (head, _) = git(root, "log", "-1", "--format=%h %s")
  head = head.strip
  var html = "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">" &
    "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>OpenSpec review</title>" &
    "<link rel=\"stylesheet\" href=\"https://fonts.googleapis.com/css2?family=Familjen+Grotesk:wght@500;700&family=Literata:ital,opsz,wght@0,7..72,400;0,7..72,600;1,7..72,400&family=JetBrains+Mono:wght@400;600&display=swap\">" &
    "<style>" & css & "</style></head><body>"
  html.add "<header class=\"mast\"><span class=\"eyebrow\">" & esc(root.lastPathPart) &
    " · OpenSpec review</span><h1>Where the changes stand</h1><div class=\"meta\">" & esc(head) &
    (if base.len > 0: " · compared with " & esc(base) else: "") & " · generated " &
    now().format("yyyy-MM-dd HH:mm") & "</div>" &
    "<nav class=\"nav\"><a href=\"#overview\">Changes</a><a href=\"#specs\">Specs</a>" &
    (if base.len > 0: "<a href=\"#raw-diff\">Diff</a>" else: "") &
    "<label><input type=\"checkbox\" id=\"show-archived\"> Show archived changes (" &
    $changes.countIt(it.archived and not it.touched) & ")</label></nav></header><main>"

  let active = changes.filterIt(not it.archived)
  html.add "<h2 id=\"overview\">Changes</h2><table class=\"overview\"><tr><th>Change</th><th>Stage</th><th>Tasks</th><th>Specs</th></tr>"
  for c in changes:
    let (done, total) = c.taskCounts
    html.add "<tr" & (if c.archived and not c.touched: " class=\"archived\"" else: "") &
      "><td><a href=\"#" & esc(c.name) & "\">" & esc(c.name) & "</a>" &
      (if c.touched: " <span class=\"pill touched\">changed</span>" else: "") & "</td><td>" & c.stage &
      "</td><td>" & $done & "/" & $total & "</td><td>" &
      c.caps.mapIt("<code>" & esc(it.name) & "</code> " & it.countsLabel).join("<br>") & "</td></tr>"
  html.add "</table>"
  if active.len == 0: html.add "<p class=\"unchanged\">No active changes.</p>"
  for c in changes: html.add renderChange(c, root)
  html.add renderSpecs(root, changes, files)
  if base.len > 0: html.add renderRawDiff(root, base, files)
  html.add "</main><footer>Generated by tools/specview.nim</footer>" & toggleJs & "</body></html>\n"
  writeFile(outPath, html)
  echo "wrote ", outPath
  if mdPath.len > 0:
    let f = open(mdPath, fmAppend)   # $GITHUB_STEP_SUMMARY is appended to
    f.write renderMarkdown(changes, base, files)
    f.close
    echo "wrote ", mdPath

when isMainModule:
  main()
