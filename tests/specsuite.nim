## The Nim examples in openspec/specs as unittest tests: each ```nim block is a test
## (named `<capability>:<line>`), and when a ```text block follows it, what the example
## prints must equal it. Used by tests/test_specs*.nim; tools/specexamples.nim checks
## the same examples on its own and can `--update` the expected output.
##
## What an example prints is captured at the file descriptor, so output from Polars
## (Rust) counts too.

import std/[macros, os, strutils, algorithm, posix, unittest]
import ../tools/specexamples

const specRoot = currentSourcePath().parentDir.parentDir / "openspec" / "specs"

type Capture* = tuple[saved: cint, path: string]

proc startCapture*(): Capture =
  flushFile stdout
  result.path = getTempDir() / "nanuq-spec-" & $getpid() & ".txt"
  let f = open(result.path, fmWrite)
  result.saved = dup(1)
  discard dup2(f.getFileHandle, 1)
  f.close

proc stopCapture*(c: Capture): string =
  flushFile stdout
  discard dup2(c.saved, 1)
  discard close(c.saved)
  result = readFile(c.path).strip(leading = false)
  removeFile c.path

macro specTests*(only: static string = ""): untyped =
  ## The examples of every spec that needs no other package, or with `only`, of that
  ## one capability (a spec that imports Arraymancer, Datamancer or db_connector).
  var caps: seq[string]
  for line in staticExec("ls " & quoteShell(specRoot)).splitLines:
    if line.len > 0 and fileExists(specRoot / line / "spec.md"): caps.add line
  caps.sort
  var imports: seq[string]
  var body = ""
  for cap in caps:
    let spec = Spec(cap: cap, exs: parseExamples(staticRead(specRoot / cap / "spec.md").splitLines))
    if spec.exs.len == 0: continue
    if (only.len > 0 and cap != only) or (only.len == 0 and spec.ownProgram): continue
    body.add "suite " & escape("spec " & cap) & ":\n"
    for ex in spec.exs:
      body.add "  test " & escape(cap & ":" & $ex.line) & ":\n"
      body.add "    let capture = startCapture()\n    try:\n      block:\n"
      for l in ex.code:
        if l.startsWith("import "):
          if l notin imports: imports.add l
        else: body.add "        " & l & "\n"
      body.add "        discard\n"
      body.add "    finally:\n      let printed = capture.stopCapture\n"
      if ex.outFirst >= 0:
        body.add "      check printed == " & escape(ex.expected.strip(leading = false)) & "\n"
      else:
        body.add "      discard printed\n"
  result = parseStmt("import nanuq, nanuq/datasets, std/[options, os, strutils]\n" &
    imports.join("\n") & "\n" & body)
