## Raw bindings to the `nanuq_ffi` Rust crate (see `src/rust/src/lib.rs`).
##
## This mirrors the C ABI one to one, in the style of an
## `nbindgen <https://github.com/arnetheduck/nbindgen>`_ generated header.
## You normally want the high level API in `nanuq` instead.
##
## Linking: the static library `libnanuq_ffi.a` comes from the first of
##
## 1. `-d:nanuqLibDir=/some/dir`, a library built or downloaded by hand;
## 2. the local cargo output in `src/rust/target/release` (git checkouts);
## 3. the prebuilt library for this platform, downloaded once from the
##    GitHub release `lib-v<version>` into a per-user cache and checked
##    against the SHA-256 in `lib-sums.txt`;
## 4. `cargo build --release` of the crate shipped with this package.
##
## `-d:nanuqLib=source` never downloads, `-d:nanuqLib=prebuilt` (or
## `-d:nanuqNoCargo`) never runs cargo, and the default `auto` allows both.
## `-d:nanuqLegacyCpu` picks the build for x86_64 CPUs without AVX2/FMA, which
## is otherwise chosen automatically on Linux. `-d:nanuqCacheDir` moves the
## cache, and `-d:nanuqReleaseUrl` downloads from a mirror of the releases
## (the checksums still apply).

import std/[os, strutils]

const
  rustDir = currentSourcePath.parentDir.parentDir / "rust"
  libFileName = "libnanuq_ffi.a"
  nanuqLib {.strdefine.} = "auto"
  nanuqLibDir {.strdefine.} = ""
  nanuqCacheDir {.strdefine.} = ""
  nanuqReleaseUrl {.strdefine.} = "https://github.com/pietroppeter/nanuq/releases/download"
  libPolicy = (when defined(nanuqNoCargo): "prebuilt" else: nanuqLib)

when libPolicy notin ["auto", "prebuilt", "source"]:
  {.error: "nanuq: -d:nanuqLib must be auto, prebuilt or source, not " & libPolicy.}

proc crateVersion(cargoToml: string): string =
  ## The `version` of the `[package]` section.
  var inPackage = false
  for line in cargoToml.splitLines:
    let l = line.strip
    if l.startsWith("["): inPackage = l == "[package]"
    elif inPackage and l.startsWith("version"):
      return l.split('=', 1)[1].strip.strip(chars = {'"'})

const nanuqLibVersion* = crateVersion(staticRead(rustDir / "Cargo.toml"))
  ## Version of the `nanuq_ffi` crate these bindings were compiled for.

proc targetTriple(): string =
  when defined(linux) and defined(amd64): "x86_64-unknown-linux-gnu"
  elif defined(linux) and defined(arm64): "aarch64-unknown-linux-gnu"
  elif defined(macosx) and defined(arm64): "aarch64-apple-darwin"
  elif defined(windows) and defined(amd64): "x86_64-pc-windows-gnu"
  else: ""

proc lacksModernCpu*(cpuinfo: string): bool =
  ## True when the first `flags` line of `/proc/cpuinfo` text misses a feature
  ## of the x86-64-v3 build.
  for line in cpuinfo.splitLines:
    if line.startsWith("flags"):
      let flags = line.split(':', 1)[1].splitWhitespace
      for f in ["avx", "avx2", "bmi1", "bmi2", "fma", "f16c", "movbe"]:
        if f notin flags: return true
      return false

proc hostLacksModernCpu(): bool =
  ## True when compiling on x86_64 Linux for x86_64 Linux and the CPU lacks a
  ## feature of the x86-64-v3 build. Elsewhere we can't tell, so false.
  when defined(linux) and defined(amd64):
    let arch = gorgeEx("uname -m")
    let info = gorgeEx("cat /proc/cpuinfo")
    arch.exitCode == 0 and arch.output.strip == "x86_64" and info.exitCode == 0 and
      lacksModernCpu(info.output)
  else:
    false

proc archiveName(): string =
  ## Release asset for this target, or "" when there is none.
  let triple = targetTriple()
  if triple.len == 0: return ""
  result = "libnanuq_ffi-" & nanuqLibVersion & "-" & triple
  if triple.startsWith("x86_64") and (defined(nanuqLegacyCpu) or hostLacksModernCpu()):
    result.add "-legacy-cpu"
  result.add ".tar.gz"

proc expectedSum(archive: string): string =
  ## SHA-256 of `archive` from lib-sums.txt (sha256sum format), or "".
  for line in staticRead(currentSourcePath.parentDir / "lib-sums.txt").splitLines:
    let parts = line.splitWhitespace
    if parts.len == 2 and parts[1].strip(chars = {'*'}) == archive:
      return parts[0].toLowerAscii

proc cacheRoot(): string =
  if nanuqCacheDir.len > 0: return nanuqCacheDir
  if getEnv("LOCALAPPDATA").len > 0: return getEnv("LOCALAPPDATA") / "nanuq"
  if dirExists(getHomeDir() / "Library" / "Caches"):
    return getHomeDir() / "Library" / "Caches" / "nanuq"
  let xdg = getEnv("XDG_CACHE_HOME")
  (if xdg.len > 0: xdg else: getHomeDir() / ".cache") / "nanuq"

proc sha256(file: string): string =
  for cmd in ["sha256sum " & quoteShell(file), "shasum -a 256 " & quoteShell(file),
              "certutil -hashfile " & quoteShell(file) & " SHA256"]:
    let r = gorgeEx(cmd)
    if r.exitCode == 0:
      for line in r.output.splitLines:
        let h = line.strip.split(' ')[0].toLowerAscii
        if h.len == 64 and h.allCharsInSet(HexDigits): return h

proc removeTmp(file: string) =
  # removeFile needs C at compile time
  discard gorgeEx((when defined(windows): "cmd /c del " else: "rm -f ") & quoteShell(file))

proc prebuiltLib(): tuple[lib, why, error: string] =
  ## Path of the cached or downloaded library, or "" and the reason why not.
  ## `error` is set when the compile must stop instead of building.
  let archive = archiveName()
  if archive.len == 0:
    return ("", "no prebuilt library for this platform", "")
  if nanuqLibVersion.endsWith("-dev"):
    return ("", "lib version " & nanuqLibVersion & " is a development version", "")
  let sum = expectedSum(archive)
  if sum.len == 0:
    return ("", "no published " & archive & " in lib-sums.txt", "")
  let dir = cacheRoot() / nanuqLibVersion / archive.replace(".tar.gz", "")
  if fileExists(dir / ".complete"):
    return (dir / libFileName, "", "")
  let url = nanuqReleaseUrl & "/lib-v" & nanuqLibVersion & "/" & archive
  echo "nanuq: downloading the prebuilt Polars wrapper " & url
  # a name of our own, so two compiles at once don't write the same archive
  let tmp = dir / ("download-" & CompileDate & "-" & CompileTime.replace(":", "") & ".tar.gz")
  let dl = gorgeEx("curl -fsSL --retry 2 --create-dirs -o " & quoteShell(tmp) & " " & url)
  if dl.exitCode != 0:
    return ("", "download of " & url & " failed: " & dl.output.strip, "")
  let actual = sha256(tmp)
  if actual != sum:
    removeTmp(tmp)
    return ("", "", "nanuq: checksum mismatch for " & url & "\n  expected " & sum &
      "\n  actual   " & actual & "\nThe download was deleted. If it persists, the " &
      "release may have been replaced: please open an issue.")
  let ex = gorgeEx("tar -xzf " & quoteShell(tmp) & " -C " & quoteShell(dir))
  removeTmp(tmp)
  if ex.exitCode != 0 or not fileExists(dir / libFileName):
    return ("", "could not unpack " & url & ": " & ex.output.strip, "")
  writeFile(dir / ".complete", url)
  (dir / libFileName, "", "")

proc findLib(): tuple[lib, error: string] =
  if nanuqLibDir.len > 0:
    if not fileExists(nanuqLibDir / libFileName):
      return ("", "nanuq: -d:nanuqLibDir has no " & libFileName & ": " & nanuqLibDir)
    return (nanuqLibDir / libFileName, "")
  let local = rustDir / "target" / "release" / libFileName
  if fileExists(local): return (local, "")
  var why = "-d:nanuqLib=source"
  if libPolicy != "source":
    let (lib, reason, error) = prebuiltLib()
    if error.len > 0: return ("", error)
    if lib.len > 0: return (lib, "")
    why = reason
  if libPolicy == "prebuilt":
    return ("", "nanuq: no Polars wrapper library (" & why &
      "). Install Rust (https://rustup.rs) and compile with -d:nanuqLib=auto, or " &
      "download a release archive and pass -d:nanuqLibDir=<dir>.")
  echo "nanuq: building the Polars wrapper with cargo (" & why &
    "), the first build takes about 10 minutes..."
  let cargo = gorgeEx("cargo build --release --manifest-path " &
                      quoteShell(rustDir / "Cargo.toml"))
  if cargo.exitCode != 0 or not fileExists(local):
    return ("", "nanuq: cargo build failed (" & why & "):\n" & cargo.output &
      "\nIs Rust installed? See https://rustup.rs")
  (local, "")

const found = findLib()
when found.error.len > 0:
  {.error: found.error.}
const libFile = found.lib
{.hint: "nanuq: linking " & libFile.}

{.passL: quoteShell(libFile).}
when defined(linux):
  {.passL: "-lpthread -ldl -lm".}
elif defined(macosx):
  {.passL: "-framework CoreFoundation -framework IOKit -framework Security -lc++".}
elif defined(windows):
  {.passL: "-lws2_32 -luserenv -lbcrypt -lntdll -lole32 -loleaut32 -lkernel32 -ladvapi32".}

type
  NqDataFrame* {.incompleteStruct.} = object
  NqLazyFrame* {.incompleteStruct.} = object
  NqExpr* {.incompleteStruct.} = object
  NqSeries* {.incompleteStruct.} = object

  NqBinOp* {.size: sizeof(cint).} = enum
    nqAdd, nqSub, nqMul, nqDiv,
    nqEq, nqNotEq, nqLt, nqLtEq, nqGt, nqGtEq,
    nqAnd, nqOr

  NqUnary* {.size: sizeof(cint).} = enum
    nqNot, nqSum, nqMean, nqMin, nqMax, nqCount,
    nqFirst, nqLast, nqNUnique, nqStd,
    nqIsNull, nqIsNotNull

{.push importc, cdecl.}

# errors and strings
proc nq_last_error*(): cstring
proc nq_string_free*(s: cstring)
proc nq_version*(): cstring

# series
proc nq_series_free*(s: ptr NqSeries)
proc nq_series_new_i64*(name: cstring, data: ptr int64, len: csize_t): ptr NqSeries
proc nq_series_new_f64*(name: cstring, data: ptr float64, len: csize_t): ptr NqSeries
proc nq_series_new_bool*(name: cstring, data: ptr bool, len: csize_t): ptr NqSeries
proc nq_series_new_str*(name: cstring, data: ptr cstring, len: csize_t): ptr NqSeries
proc nq_series_new_i64_opt*(name: cstring, data: ptr int64, valid: ptr bool, len: csize_t): ptr NqSeries
proc nq_series_new_f64_opt*(name: cstring, data: ptr float64, valid: ptr bool, len: csize_t): ptr NqSeries
proc nq_series_new_bool_opt*(name: cstring, data: ptr bool, valid: ptr bool, len: csize_t): ptr NqSeries
proc nq_series_new_str_opt*(name: cstring, data: ptr cstring, valid: ptr bool, len: csize_t): ptr NqSeries

# dataframe
proc nq_df_free*(df: ptr NqDataFrame)
proc nq_df_new*(series: ptr ptr NqSeries, n: csize_t): ptr NqDataFrame
proc nq_df_read_csv*(path: cstring, nullValues: ptr cstring, n: csize_t): ptr NqDataFrame
proc nq_df_write_csv*(df: ptr NqDataFrame, path: cstring): bool
proc nq_df_height*(df: ptr NqDataFrame): int64
proc nq_df_width*(df: ptr NqDataFrame): int64
proc nq_df_to_string*(df: ptr NqDataFrame): cstring
proc nq_df_head*(df: ptr NqDataFrame, n: csize_t): ptr NqDataFrame
proc nq_df_column_name*(df: ptr NqDataFrame, idx: csize_t): cstring
proc nq_df_column_dtype*(df: ptr NqDataFrame, name: cstring): cstring
proc nq_df_get_i64*(df: ptr NqDataFrame, name: cstring, row: csize_t, output: ptr int64): bool
proc nq_df_get_f64*(df: ptr NqDataFrame, name: cstring, row: csize_t, output: ptr float64): bool
proc nq_df_get_bool*(df: ptr NqDataFrame, name: cstring, row: csize_t, output: ptr bool): bool
proc nq_df_get_str*(df: ptr NqDataFrame, name: cstring, row: csize_t): cstring

# whole columns and nulls
proc nq_df_null_count*(df: ptr NqDataFrame, name: cstring): int64
proc nq_df_cell_is_null*(df: ptr NqDataFrame, name: cstring, row: csize_t, output: ptr bool): bool
proc nq_df_cell_fmt*(df: ptr NqDataFrame, name: cstring, row: csize_t, str_len: csize_t): cstring
proc nq_df_column_i64*(df: ptr NqDataFrame, name: cstring, values: ptr int64, valid: ptr bool,
                       len: csize_t): bool
proc nq_df_column_f64*(df: ptr NqDataFrame, name: cstring, values: ptr float64, valid: ptr bool,
                       len: csize_t): bool
proc nq_df_column_bool*(df: ptr NqDataFrame, name: cstring, values: ptr bool, valid: ptr bool,
                        len: csize_t): bool
proc nq_df_column_str_size*(df: ptr NqDataFrame, name: cstring): int64
proc nq_df_column_str*(df: ptr NqDataFrame, name: cstring, data: ptr uint8, dataLen: csize_t,
                       offsets: ptr uint64, valid: ptr bool, len: csize_t): bool

# expressions
proc nq_expr_free*(e: ptr NqExpr)
proc nq_expr_col*(name: cstring): ptr NqExpr
proc nq_expr_lit_i64*(v: int64): ptr NqExpr
proc nq_expr_lit_f64*(v: float64): ptr NqExpr
proc nq_expr_lit_bool*(v: bool): ptr NqExpr
proc nq_expr_lit_str*(v: cstring): ptr NqExpr
proc nq_expr_binary*(a: ptr NqExpr, op: NqBinOp, b: ptr NqExpr): ptr NqExpr
proc nq_expr_unary*(e: ptr NqExpr, op: NqUnary): ptr NqExpr
proc nq_expr_fill_null*(e: ptr NqExpr, value: ptr NqExpr): ptr NqExpr
proc nq_expr_alias*(e: ptr NqExpr, name: cstring): ptr NqExpr
proc nq_expr_to_string*(e: ptr NqExpr): cstring

# lazy frames
proc nq_lf_free*(lf: ptr NqLazyFrame)
proc nq_df_lazy*(df: ptr NqDataFrame): ptr NqLazyFrame
proc nq_lf_collect*(lf: ptr NqLazyFrame): ptr NqDataFrame
proc nq_lf_select*(lf: ptr NqLazyFrame, e: ptr ptr NqExpr, n: csize_t): ptr NqLazyFrame
proc nq_lf_with_columns*(lf: ptr NqLazyFrame, e: ptr ptr NqExpr, n: csize_t): ptr NqLazyFrame
proc nq_lf_filter*(lf: ptr NqLazyFrame, predicate: ptr NqExpr): ptr NqLazyFrame
proc nq_lf_group_by_agg*(lf: ptr NqLazyFrame, by: ptr ptr NqExpr, nby: csize_t,
                         aggs: ptr ptr NqExpr, naggs: csize_t): ptr NqLazyFrame
proc nq_lf_sort*(lf: ptr NqLazyFrame, by: cstring, descending: bool): ptr NqLazyFrame
proc nq_lf_drop_nulls*(lf: ptr NqLazyFrame, names: ptr cstring, n: csize_t): ptr NqLazyFrame
proc nq_lf_limit*(lf: ptr NqLazyFrame, n: uint32): ptr NqLazyFrame
proc nq_lf_explain*(lf: ptr NqLazyFrame): cstring

{.pop.}

let compiledFor = nanuqLibVersion
if $nq_version() != compiledFor:
  raise newException(Defect, "nanuq: the linked Polars wrapper library is version " &
    $nq_version() & " but these bindings were compiled for " & compiledFor &
    ". Rebuild it or point -d:nanuqLibDir at a matching library.")
