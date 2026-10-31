## specexamples: compile and run the Nim examples in the OpenSpec specs.
##
## Every ```nim block in `openspec/specs/*/spec.md` is an example. It is compiled with
## `nanuq`, `nanuq/datasets` and `std/[options, os, strutils]` already imported, and run.
## An example's own `import` lines are moved to the top of the program. When a ```text
## block follows it (only blank lines between), the example's output must equal it.
## Change deltas in `openspec/changes/` are not checked: they describe API that may not
## exist yet.
##
## Usage:
##   nim r tools/specexamples.nim [--update] [-d:define ...] [spec ...]
##
## `--update` rewrites the ```text blocks with the actual output instead of failing.
## `-d:`/`--define:` flags are passed to the compile (CI uses `-d:nanuqNoCargo`).
## Extra arguments limit the run to those capabilities (e.g. `expressions`).

import std/[os, osproc, strutils, parseopt, algorithm]

const prelude = "import nanuq, nanuq/datasets, std/[options, os, strutils]\n"
const marker = "@@nanuq-example@@"

type Example = object
  line: int            ## 1-based line of the ```nim fence
  code: seq[string]
  outFirst, outLast: int  ## 0-based line range of the text body, -1 when absent
  expected: string

proc parseExamples(lines: seq[string]): seq[Example] =
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

proc program(exs: seq[Example]): string =
  result = prelude
  var body = ""
  for n, ex in exs:
    body.add "echo \"" & marker & $n & "\"\nblock:\n"
    for l in ex.code:
      if l.startsWith("import "): result.add l & "\n"
      else: body.add "  " & l & "\n"
    body.add "  discard\n"
  result.add body

proc main() =
  var update = false
  var only: seq[string]
  var flags = ""
  for kind, key, val in getopt():
    case kind
    of cmdLongOption, cmdShortOption:
      if key == "update": update = true
      elif key in ["d", "define"]: flags.add " -d:" & quoteShell(val)
    of cmdArgument: only.add key
    else: discard
  let root = currentSourcePath.parentDir.parentDir
  let tmp = getTempDir() / "nanuq-specexamples"
  createDir tmp
  var failures = 0
  var total = 0
  var dirs: seq[string]
  for dir in walkDirs(root / "openspec" / "specs" / "*"): dirs.add dir
  dirs.sort
  for dir in dirs:
    let cap = dir.lastPathPart
    if only.len > 0 and cap notin only: continue
    let path = dir / "spec.md"
    if not fileExists(path): continue
    var lines = readFile(path).splitLines
    let exs = parseExamples(lines)
    if exs.len == 0: continue
    total += exs.len
    let src = tmp / ("spec_" & cap.replace('-', '_') & ".nim")
    writeFile(src, program(exs))
    let (output, code) = execCmdEx("nim r --hints:off --warnings:off" & flags & " -p:" &
      quoteShell(root / "src") & " " & quoteShell(src))
    if code != 0:
      echo "FAIL ", cap, ": the examples do not compile or run\n", output
      inc failures
      continue
    # Split the output at the markers; whatever comes before the first is build noise.
    var outs = newSeq[string](exs.len)
    var cur = -1
    var buf: seq[string]
    for l in output.splitLines:
      if l.startsWith(marker):
        if cur >= 0: outs[cur] = buf.join("\n").strip(leading = false)
        cur = parseInt(l[marker.len .. ^1]); buf = @[]
      elif cur >= 0: buf.add l
    if cur >= 0: outs[cur] = buf.join("\n").strip(leading = false)
    var changed = false
    for n in countdown(exs.high, 0):
      let ex = exs[n]
      if ex.outFirst < 0: continue
      if outs[n] != ex.expected.strip(leading = false):
        if update:
          lines[ex.outFirst .. ex.outLast] = outs[n].splitLines
          changed = true
        else:
          echo "FAIL ", path.relativePath(root), ":", ex.line, "\n--- expected\n", ex.expected,
            "\n--- actual\n", outs[n]
          inc failures
    if changed:
      writeFile(path, lines.join("\n"))
      echo "updated ", path.relativePath(root)
    echo "ok ", cap, " (", exs.len, " examples)"
  echo total, " examples, ", failures, " failures"
  if failures > 0: quit 1

main()
