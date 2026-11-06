## specexamples: compile and run the Nim examples in the OpenSpec specs.
##
## Every ```nim block in `openspec/specs/*/spec.md` is an example. It is compiled with
## `nanuq`, `nanuq/datasets` and `std/[options, os, strutils]` already imported, and run.
## An example's own `import` lines are moved to the top of the program. When a ```text
## block follows it (only blank lines between), the example's output must equal it.
## Change deltas in `openspec/changes/` are not checked: they describe API that may not
## exist yet.
##
## All specs go into ONE program, compiled and linked once (each example in its own
## `block`). If it does not compile, each spec is compiled on its own to say which
## one breaks.
##
## Usage:
##   nim r tools/specexamples.nim [--update] [-d:define ...] [spec ...]
##
## `--update` rewrites the ```text blocks with the actual output instead of failing.
## `-d:`/`--define:` flags are passed to the compile (CI uses `-d:nanuqNoCargo`).
## Extra arguments limit the run to those capabilities (e.g. `expressions`).

import std/[os, osproc, strutils, parseopt, algorithm, tables]
import ../tests/pluginfixture

const prelude = "import nanuq, nanuq/datasets, std/[options, os, strutils]\n"
const marker = "@@nanuq-example@@"

type Example* = object
  line*: int            ## 1-based line of the ```nim fence
  code*: seq[string]
  outFirst*, outLast*: int  ## 0-based line range of the text body, -1 when absent
  expected*: string

proc parseExamples*(lines: seq[string]): seq[Example] =
  var i = 0
  while i < lines.len:
    if lines[i].strip == "```nim":
      var ex = Example(line: i + 1, outFirst: -1, outLast: -1)
      inc i
      while i < lines.len and lines[i].strip != "```":
        ex.code.add lines[i]; inc i
      inc i
      var j = i
      while j < lines.len and lines[j].strip.len == 0: inc j
      if j < lines.len and lines[j].strip == "```text":
        ex.outFirst = j + 1
        var k = j + 1
        while k < lines.len and lines[k].strip != "```": inc k
        ex.outLast = k - 1
        ex.expected = lines[ex.outFirst .. ex.outLast].join("\n")
        i = k + 1
      result.add ex
    else:
      inc i

type Spec* = object
  cap*, path*: string
  lines*: seq[string]
  exs*: seq[Example]

proc ownProgram*(s: Spec): bool =
  ## Imports anything but the standard library and Nanuq's own modules.
  for ex in s.exs:
    for l in ex.code:
      if l.startsWith("import "):
        for m in l["import ".len .. ^1].split(','):
          let m = m.strip
          if not (m.startsWith("std/") or m.startsWith("nanuq")) or
             m in ["nanuq/arraymancer", "nanuq/datamancer", "nanuq/database"]:
            return true

proc program(specs: seq[Spec]): string =
  var imports: seq[string]
  var body = ""
  for s in specs:
    for n, ex in s.exs:
      body.add "echo \"" & marker & s.cap & marker & $n & "\"\nblock:\n"
      for l in ex.code:
        if l.startsWith("import "):
          if l notin imports: imports.add l
        else: body.add "  " & l & "\n"
      body.add "  discard\n"
  result = prelude & imports.join("\n") & "\n" & body

proc compileAndRun(src, flags, root, tmp: string): (string, int) =
  # removed after the run: every binary links the whole static Polars library
  let cache = tmp / ("cache_" & src.splitFile.name)
  result = execCmdEx("nim r --hints:off --warnings:off" & flags & " -p:" &
    quoteShell(root / "src") & " --nimcache:" & quoteShell(cache) & " " & quoteShell(src))
  removeDir(cache)

proc main() =
  var update = false
  var only: seq[string]
  var flags = ""
  for kind, key, val in getopt():
    case kind
    of cmdLongOption, cmdShortOption:
      if key == "update": update = true
      elif key in ["d", "define"]: flags.add " -d:" & quoteShell(val)
      elif key == "passL": flags.add " --passL:" & quoteShell(val)
    of cmdArgument: only.add key
    else: discard
  # the fast linking of config.nims, which does not reach programs in the temp dir
  when defined(linux):
    if findExe("ld.lld").len > 0 and "nanuqKeepDebugInfo" notin flags:
      flags.add " --passL:-fuse-ld=lld --passL:-Wl,--strip-debug"
  let root = currentSourcePath.parentDir.parentDir
  discard doubleItLib()   # the plugin the expression-plugins example loads
  let tmp = getTempDir() / "nanuq-specexamples"
  createDir tmp
  var failures = 0
  var total = 0
  var dirs: seq[string]
  for dir in walkDirs(root / "openspec" / "specs" / "*"): dirs.add dir
  dirs.sort
  var specs: seq[Spec]
  for dir in dirs:
    let cap = dir.lastPathPart
    if only.len > 0 and cap notin only: continue
    let path = dir / "spec.md"
    if not fileExists(path): continue
    let lines = readFile(path).splitLines
    let exs = parseExamples(lines)
    if exs.len == 0: continue
    total += exs.len
    specs.add Spec(cap: cap, path: path, lines: lines, exs: exs)
  # Specs that import other packages (Arraymancer, Datamancer, db_connector) get a
  # program of their own: their names would clash with the others' (quantile, ...).
  var shared: seq[Spec]
  var groups: seq[(string, seq[Spec])]
  for s in specs:
    if s.ownProgram: groups.add (s.cap, @[s])
    else: shared.add s
  if shared.len > 0: groups.insert(("all", shared), 0)
  var outs: Table[string, seq[string]]
  for s in specs: outs[s.cap] = newSeq[string](s.exs.len)
  var broken: seq[string]
  for (name, group) in groups:
    let src = tmp / ("spec_" & name.replace('-', '_') & ".nim")
    writeFile(src, program(group))
    let (output, code) = compileAndRun(src, flags, root, tmp)
    if code != 0:
      if group.len == 1:
        echo "FAIL ", name, ": the examples do not compile or run\n", output
        inc failures
      else:  # find the spec(s) that break it
        var found = false
        for s in group:
          let one = tmp / ("spec_" & s.cap.replace('-', '_') & ".nim")
          writeFile(one, program(@[s]))
          let (o, c) = compileAndRun(one, flags, root, tmp)
          if c != 0:
            echo "FAIL ", s.cap, ": the examples do not compile or run\n", o
            inc failures
            found = true
        if not found:
          echo "FAIL: the examples compile and run one spec at a time, but not together\n", output
          inc failures
      for s in group: broken.add s.cap
      continue
    # Split the output at the markers; whatever comes before the first is build noise.
    var cap = ""
    var cur = -1
    var buf: seq[string]
    template flush() =
      if cur >= 0: outs[cap][cur] = buf.join("\n").strip(leading = false)
    for l in output.splitLines:
      if l.startsWith(marker):
        flush()
        let parts = l[marker.len .. ^1].split(marker)
        cap = parts[0]; cur = parseInt(parts[1]); buf = @[]
      elif cur >= 0: buf.add l
    flush()
  for s in specs:
    if s.cap in broken: continue
    var lines = s.lines
    var changed = false
    for n in countdown(s.exs.high, 0):
      let ex = s.exs[n]
      if ex.outFirst < 0: continue
      let got = outs[s.cap][n]
      if got != ex.expected.strip(leading = false):
        if update:
          lines[ex.outFirst .. ex.outLast] = got.splitLines
          changed = true
        else:
          echo "FAIL ", s.path.relativePath(root), ":", ex.line, "\n--- expected\n", ex.expected,
            "\n--- actual\n", got
          inc failures
    if changed:
      writeFile(s.path, lines.join("\n"))
      echo "updated ", s.path.relativePath(root)
    echo "ok ", s.cap, " (", s.exs.len, " examples)"
  echo total, " examples, ", failures, " failures"
  if failures > 0: quit 1

when isMainModule:
  main()
