## The test plugin `tests/data/plugins/double_it.nim`, built as a library next to its
## source (`tests/data/plugins/libdouble_it.so` on Linux) the first time a test or a
## spec example needs it, and again when the source changes.

import std/[os, osproc, strutils]

const pluginDir = currentSourcePath.parentDir / "data" / "plugins"

proc doubleItLib*(): string =
  ## The path of the built plugin library.
  result = pluginDir / (DynlibFormat % "double_it")
  let src = pluginDir / "double_it.nim"
  if fileExists(result) and fileNewer(result, src): return
  let (output, code) = execCmdEx("nim c --app:lib -d:useMalloc --threads:on --hints:off " &
    "--nimcache:" & quoteShell(getTempDir() / "nanuq_test_plugin_cache") & " --out:" &
    quoteShell(result) & " " & quoteShell(src))
  doAssert code == 0, output
