## Runs every test file (tests/test_*.nim) in one program: one compile, one link.
## That includes the examples in openspec/specs (test_specs*.nim, see specsuite.nim).
##
##   nim r tests/all.nim              # all tests
##   nim r tests/all.nim "csv::*"     # unittest filters work as usual
##   nim r tests/test_csv.nim         # a single file, as before
##
## Test files are found at compile time, so a new one needs no list. Each file's suites
## run when its module is initialised, in file-name order. Files that need an optional
## package (Datamancer, Arraymancer, db_connector) are left out when it is not installed.

import std/[macros, os, strutils, algorithm]

const optional = [("test_datamancer", "datamancer"), ("test_arraymancer", "arraymancer"),
                  ("test_database", "db_connector/db_sqlite"),
                  ("test_specs_datamancer", "datamancer"),
                  ("test_specs_arraymancer", "arraymancer"),
                  ("test_specs_database", "db_connector/db_sqlite")]

macro importTests(): untyped =
  let dir = currentSourcePath().parentDir
  var names: seq[string]
  for line in staticExec("ls " & quoteShell(dir)).splitLines:
    if line.startsWith("test_") and line.endsWith(".nim"): names.add line[0 ..< ^4]
  names.sort
  var src = ""
  for name in names:
    var needs = ""
    for (t, m) in optional:
      if t == name: needs = m
    let imp = "import \"" & dir / name & "\"\n"  # absolute: parseStmt has no file to be relative to
    if needs.len == 0:
      src.add imp
    else:  # the check nimib's moduleAvailable does
      src.add "when (compiles do: import " & needs & "): " & imp &
        "else: {.hint: \"tests/all.nim: skipping " & name & " (needs " & needs & ")\".}\n"
  result = parseStmt(src)

{.warning[UnusedImport]: off.}
importTests()
