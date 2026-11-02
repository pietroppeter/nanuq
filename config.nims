# Lets `nim r examples/...` and `nim r tests/...` find the package from the repo.
switch("path", thisDir() & "/src")

# Linking the static Polars library (~300 MB) is most of a build: GNU ld takes ~9 s per
# binary, lld ~0.7 s once the debug info (only the library's, Nim's stack traces don't
# use it) is left out. Used when lld is installed (Linux only; macOS's linker is fast).
when defined(linux) and not defined(nanuqKeepDebugInfo):
  if findExe("ld.lld").len > 0:
    switch("passL", "-fuse-ld=lld")
    switch("passL", "-Wl,--strip-debug")
