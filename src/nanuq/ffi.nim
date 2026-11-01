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
    "), this compiles Polars and its dependencies..."
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
  NqDataType* {.incompleteStruct.} = object
    ## A Polars data type handle (0.5), nested ones included.
  NqSeries* {.incompleteStruct.} = object

  NqBinOp* {.size: sizeof(cint).} = enum
    nqAdd, nqSub, nqMul, nqDiv,
    nqEq, nqNotEq, nqLt, nqLtEq, nqGt, nqGtEq,
    nqAnd, nqOr,
    nqMod, nqFloorDiv, nqPow

  NqUnary* {.size: sizeof(cint).} = enum
    nqNot, nqSum, nqMean, nqMin, nqMax, nqCount,
    nqFirst, nqLast, nqNUnique, nqStd,
    nqIsNull, nqIsNotNull,
    nqAbs, nqMedian, nqLen, nqNeg, nqNullCount,
    # 0.4: elementwise math
    nqSqrt, nqCbrt, nqExp, nqLog10, nqLog1p, nqSign, nqFloor, nqCeil,
    nqSin, nqCos, nqTan, nqCot, nqArcSin, nqArcCos, nqArcTan,
    nqSinh, nqCosh, nqTanh, nqArcSinh, nqArcCosh, nqArcTanh, nqDegrees, nqRadians,
    nqIsNan, nqIsNotNan, nqIsFinite, nqIsInfinite, nqDropNans, nqDropNulls,
    # 0.4: cumulative and shift
    nqProduct, nqMode, nqArgMin, nqArgMax, nqRleId, nqPeakMax, nqPeakMin,
    # 0.4: value functions
    nqUnique, nqUniqueStable, nqArgUnique, nqIsUnique, nqIsDuplicated, nqIsFirstDistinct,
    nqIsLastDistinct, nqUniqueCounts, nqApproxNUnique, nqReverse
  NqCum* {.size: sizeof(cint).} = enum
    nqcSum, nqcProd, nqcMin, nqcMax, nqcCount
  NqBinaryFn* {.size: sizeof(cint).} = enum
    nqbLog, nqbArctan2, nqbDot, nqbFillNan, nqbInterpolateBy,
    nqbGather, nqbTopK, nqbBottomK, nqbIndexOf,
    nqbSearchSortedAny, nqbSearchSortedLeft, nqbSearchSortedRight
  NqRolling* {.size: sizeof(cint).} = enum
    nqrSum, nqrMean, nqrMin, nqrMax, nqrStd, nqrVar, nqrMedian, nqrQuantile
  NqLabel* {.size: sizeof(cint).} = enum
    nqlLeft, nqlRight, nqlDataPoint
  NqStartBy* {.size: sizeof(cint).} = enum
    nqsWindowBound, nqsDataPoint, nqsMonday, nqsTuesday, nqsWednesday, nqsThursday,
    nqsFriday, nqsSaturday, nqsSunday
  NqHorizontal* {.size: sizeof(cint).} = enum
    nqhSum, nqhMean, nqhMin, nqhMax, nqhAll, nqhAny, nqhCoalesce

  NqDtype* {.size: sizeof(cint).} = enum
    ## Same order as `NqDtype` in lib.rs and `DataTypeKind` in nanuq.nim.
    nqBoolean, nqInt8, nqInt16, nqInt32, nqInt64,
    nqUInt8, nqUInt16, nqUInt32, nqUInt64,
    nqFloat32, nqFloat64, nqString, nqNull, nqDate, nqDatetime, nqDuration, nqTime,
    nqCategorical, nqEnum, nqList, nqArray, nqStruct, nqOther
  NqTimeUnit* {.size: sizeof(cint).} = enum
    nquNanoseconds, nquMicroseconds, nquMilliseconds
  NqClosedWindow* {.size: sizeof(cint).} = enum
    nqwLeft, nqwRight, nqwBoth, nqwNone
  NqDtypeSpec* = object
    ## A data type with its parameters (`NqDtypeSpec` in lib.rs).
    code*: NqDtype
    timeUnit*: NqTimeUnit
    timeZone*: cstring
    categories*: ptr cstring
    nCategories*: csize_t
    nested*: ptr NqDataType   ## for List, Array and Struct: the whole type

  NqJoinType* {.size: sizeof(cint).} = enum
    nqjInner, nqjLeft, nqjRight, nqjFull, nqjSemi, nqjAnti, nqjCross
  NqJoinValidation* {.size: sizeof(cint).} = enum
    nqvManyToMany, nqvManyToOne, nqvOneToMany, nqvOneToOne
  NqMaintainOrderJoin* {.size: sizeof(cint).} = enum
    nqoNone, nqoLeft, nqoRight, nqoLeftRight, nqoRightLeft
  NqConcat* {.size: sizeof(cint).} = enum
    nqcVertical, nqcVerticalRelaxed, nqcHorizontal, nqcDiagonal, nqcDiagonalRelaxed
  NqUniqueKeepStrategy* {.size: sizeof(cint).} = enum
    nqkFirst, nqkLast, nqkNone, nqkAny
  NqClosedInterval* {.size: sizeof(cint).} = enum
    nqiBoth, nqiLeft, nqiRight, nqiNone
  NqQuantileMethod* {.size: sizeof(cint).} = enum
    nqqNearest, nqqLower, nqqHigher, nqqMidpoint, nqqLinear, nqqEquiprobable
  NqFillNullStrategy* {.size: sizeof(cint).} = enum
    nqfForward, nqfBackward, nqfMean, nqfMin, nqfMax, nqfZero, nqfOne
  NqRoundMode* {.size: sizeof(cint).} = enum
    nqrHalfToEven, nqrHalfAwayFromZero, nqrToZero
  NqDtypeClass* {.size: sizeof(cint).} = enum
    nqcNumeric, nqcInteger, nqcSignedInteger, nqcUnsignedInteger, nqcFloat
  NqQuoteStyle* {.size: sizeof(cint).} = enum
    nqsNecessary, nqsAlways, nqsNonNumeric, nqsNever
  NqCatOp* {.size: sizeof(cint).} = enum
    nqcGetCategories, nqcLenBytes, nqcLenChars, nqcStartsWith, nqcEndsWith, nqcSlice
  NqParquetCompression* {.size: sizeof(cint).} = enum
    nqpLz4, nqpUncompressed, nqpSnappy, nqpGzip, nqpBrotli, nqpZstd
  NqIpcCompression* {.size: sizeof(cint).} = enum
    nqiUncompressed, nqiLz4, nqiZstd
  NqErrorKind* {.size: sizeof(cint).} = enum
    nqeGeneric, nqeColumnNotFound, nqeCompute, nqeDuplicate, nqeInvalidOperation, nqeIo,
    nqeNoData, nqeOutOfBounds, nqeSchema, nqeSchemaFieldNotFound, nqeShape,
    nqeStructFieldNotFound, nqeSql
  NqDtOp* {.size: sizeof(cint).} = enum
    nqdYear, nqdIsoYear, nqdQuarter, nqdMonth, nqdWeek, nqdWeekday, nqdDay, nqdOrdinalDay,
    nqdHour, nqdMinute, nqdSecond, nqdMillisecond, nqdMicrosecond, nqdNanosecond, nqdDate,
    nqdTime, nqdIsLeapYear, nqdDaysInMonth, nqdMonthStart, nqdMonthEnd, nqdTimestamp,
    nqdCastTimeUnit, nqdToString, nqdTruncate, nqdRound, nqdOffsetBy, nqdConvertTimeZone,
    nqdReplaceTimeZone, nqdCombine, nqdTotalDays, nqdTotalHours, nqdTotalMinutes,
    nqdTotalSeconds, nqdTotalMilliseconds, nqdTotalMicroseconds, nqdTotalNanoseconds
  NqRankMethod* {.size: sizeof(cint).} = enum
    nqkAverage, nqkMin, nqkMax, nqkDense, nqkOrdinal, nqkRandom
  NqStrOp* {.size: sizeof(cint).} = enum
    nqtLenChars, nqtLenBytes, nqtToUppercase, nqtToLowercase, nqtStripChars,
    nqtStripCharsStart, nqtStripCharsEnd, nqtStripPrefix, nqtStripSuffix, nqtStartsWith,
    nqtEndsWith, nqtContains, nqtFind, nqtCountMatches, nqtExtract, nqtReplace,
    nqtReplaceAll, nqtSlice, nqtHead, nqtTail, nqtPadStart, nqtPadEnd, nqtZfill,
    nqtReverse, nqtJoin, nqtToTitlecase
  NqListOp* {.size: sizeof(cint).} = enum
    nqlLen, nqlSum, nqlMin, nqlMax, nqlMean, nqlMedian, nqlStd, nqlVar, nqlFirst, nqlLast,
    nqlArgMin, nqlArgMax, nqlNUnique, nqlAny, nqlAll, nqlGet, nqlGather, nqlGatherEvery,
    nqlSlice, nqlHead, nqlTail, nqlContains, nqlCountMatches, nqlJoin, nqlSort, nqlReverse,
    nqlUnique, nqlDropNulls, nqlDiff, nqlShift, nqlSampleN, nqlSampleFraction, nqlFilter,
    nqlUnion, nqlSetDifference, nqlSetIntersection, nqlSetSymmetricDifference, nqlToArray,
    nqlToStruct, nqlEval, nqlAgg, nqlExplode
  NqStrNestedOp* {.size: sizeof(cint).} = enum
    nqsSplit, nqsSplitExact, nqsSplitN, nqsExtractAll, nqsExtractGroups, nqsContainsAny,
    nqsReplaceMany, nqsExtractMany, nqsFindMany, nqsJsonDecode, nqsJsonPathMatch
  NqStructOp* {.size: sizeof(cint).} = enum
    nqfFieldByName, nqfFieldByNames, nqfFieldByIndex, nqfRenameFields, nqfWithFields,
    nqfJsonEncode
  NqArrOp* {.size: sizeof(cint).} = enum
    nqaLen, nqaSum, nqaMin, nqaMax, nqaMean, nqaMedian, nqaStd, nqaVar, nqaArgMin, nqaArgMax,
    nqaGet, nqaJoin, nqaContains, nqaCountMatches, nqaSort, nqaSlice, nqaHead, nqaTail,
    nqaShift, nqaToList, nqaToStruct, nqaExplode, nqaEval, nqaAgg

{.push importc, cdecl.}

# errors and strings
proc nq_last_error*(): cstring
proc nq_last_error_kind*(): NqErrorKind
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
proc nq_lf_scan_csv*(path: cstring, data: ptr uint8, dataLen: csize_t,
                     separator: uint8, hasHeader: bool,
                     nullValues: ptr cstring, nNulls: csize_t,
                     overrideNames: ptr cstring, overrideDtypes: ptr NqDtypeSpec,
                     nOverrides: csize_t, skipRows: csize_t, nRows: int64,
                     inferSchemaLength: int64,
                     ignoreErrors, decimalComma, tryParseDates: bool): ptr NqLazyFrame
proc nq_df_write_csv*(df: ptr NqDataFrame, path: cstring, separator: uint8,
                      includeHeader: bool, nullValue: cstring, quoteStyle: NqQuoteStyle,
                      floatPrecision: int32, decimalComma: bool): bool
proc nq_lf_scan_parquet*(path: cstring, data: ptr uint8, dataLen: csize_t, nRows: int64,
                         rowIndexName: cstring, rowIndexOffset: uint32,
                         lowMemory: bool): ptr NqLazyFrame
proc nq_lf_scan_ipc*(path: cstring, data: ptr uint8, dataLen: csize_t, nRows: int64,
                     rowIndexName: cstring, rowIndexOffset: uint32): ptr NqLazyFrame
proc nq_df_write_parquet*(df: ptr NqDataFrame, path: cstring,
                          compression: NqParquetCompression, level: int32,
                          statistics: bool, rowGroupSize: int64): bool
proc nq_df_write_ipc*(df: ptr NqDataFrame, path: cstring,
                      compression: NqIpcCompression): bool
proc nq_df_height*(df: ptr NqDataFrame): int64
proc nq_df_width*(df: ptr NqDataFrame): int64
proc nq_df_to_string*(df: ptr NqDataFrame): cstring
proc nq_df_head*(df: ptr NqDataFrame, n: csize_t): ptr NqDataFrame
proc nq_df_column_name*(df: ptr NqDataFrame, idx: csize_t): cstring
proc nq_df_column_dtype*(df: ptr NqDataFrame, name: cstring): cstring
proc nq_df_column_dtype_kind*(df: ptr NqDataFrame, name: cstring): int32
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
proc nq_expr_binary_fn*(a, b: ptr NqExpr, op: NqBinaryFn): ptr NqExpr
proc nq_expr_clip*(e, lo, hi: ptr NqExpr): ptr NqExpr
proc nq_expr_shift*(e: ptr NqExpr, n: int64, fill: ptr NqExpr): ptr NqExpr
proc nq_expr_diff*(e: ptr NqExpr, n: int64, drop: bool): ptr NqExpr
proc nq_expr_pct_change*(e: ptr NqExpr, n: int64): ptr NqExpr
proc nq_expr_cum*(e: ptr NqExpr, op: NqCum, reverse: bool): ptr NqExpr
proc nq_expr_moment*(e: ptr NqExpr, kurtosis, fisher, bias: bool): ptr NqExpr
proc nq_expr_rolling*(e: ptr NqExpr, op: NqRolling, window, minSamples: csize_t,
                      center: bool, weights: ptr cdouble, nWeights: csize_t, quantile: cdouble,
                      meth: NqQuantileMethod, ddof: uint8): ptr NqExpr
proc nq_expr_rolling_by*(e, by: ptr NqExpr, op: NqRolling, window: cstring,
                         minSamples: csize_t, closed: NqClosedWindow, quantile: cdouble,
                         meth: NqQuantileMethod, ddof: uint8): ptr NqExpr
proc nq_expr_ewm*(e: ptr NqExpr, op: uint8, alpha: cdouble, adjust, bias: bool,
                  minSamples: csize_t, ignoreNulls: bool): ptr NqExpr
proc nq_expr_interpolate*(e: ptr NqExpr, nearest: bool): ptr NqExpr
proc nq_expr_sort*(e: ptr NqExpr, descending, nullsLast, arg: bool): ptr NqExpr
proc nq_expr_sort_by*(e: ptr NqExpr, by: ptr ptr NqExpr, n: csize_t, descending: ptr bool,
                      nDesc: csize_t): ptr NqExpr
proc nq_expr_top_k_by*(e: ptr NqExpr, k: csize_t, by: ptr ptr NqExpr, n: csize_t,
                       reverse: ptr bool, nRev: csize_t, bottom: bool): ptr NqExpr
proc nq_expr_slice*(e: ptr NqExpr, offset, len: int64): ptr NqExpr
proc nq_expr_gather_every*(e: ptr NqExpr, n, offset: csize_t): ptr NqExpr
proc nq_expr_replace*(e, old, new: ptr NqExpr, strict: bool, default: ptr NqExpr): ptr NqExpr
proc nq_expr_cut*(e: ptr NqExpr, breaks: ptr cdouble, n: csize_t, labels: ptr cstring,
                  nLabels: csize_t, leftClosed, quantile, allowDuplicates: bool): ptr NqExpr
proc nq_expr_horizontal*(es: ptr ptr NqExpr, n: csize_t, op: NqHorizontal,
                         ignoreNulls: bool): ptr NqExpr
proc nq_expr_int_range*(start, stop: ptr NqExpr, step: int64, spec: ptr NqDtypeSpec): ptr NqExpr
proc nq_expr_linear_space*(start, stop, num: ptr NqExpr, closed: NqClosedInterval): ptr NqExpr
proc nq_expr_repeat*(value, n: ptr NqExpr): ptr NqExpr
proc nq_expr_corr*(a, b: ptr NqExpr, meth, ddof: uint8, propagateNans: bool): ptr NqExpr
proc nq_lf_pivot*(lf: ptr NqLazyFrame, on: ptr cstring, nOn: csize_t, onColumns: ptr NqDataFrame,
                  index: ptr cstring, nIndex: csize_t, values: ptr cstring, nValues: csize_t,
                  agg: ptr NqExpr, maintainOrder: bool, separator: cstring): ptr NqLazyFrame
proc nq_lf_unpivot*(lf: ptr NqLazyFrame, on: ptr cstring, nOn: csize_t, index: ptr cstring,
                    nIndex: csize_t, variableName, valueName: cstring): ptr NqLazyFrame
proc nq_df_transpose*(df: ptr NqDataFrame, keepNamesAs: cstring, newNames: ptr cstring,
                      nNames: csize_t): ptr NqDataFrame
proc nq_df_partition_by*(df: ptr NqDataFrame, by: ptr cstring, n: csize_t,
                         maintainOrder, includeKey: bool, outLen: ptr csize_t): ptr ptr NqDataFrame
proc nq_df_array_free*(p: ptr ptr NqDataFrame, len: csize_t)
proc nq_df_to_dummies*(df: ptr NqDataFrame, columns: ptr cstring, n: csize_t, separator: cstring,
                       dropFirst, dropNulls: bool): ptr NqDataFrame
proc nq_expr_element*(): ptr NqExpr
proc nq_expr_item*(e: ptr NqExpr, allowEmpty: bool): ptr NqExpr
proc nq_lf_group_by_dynamic_agg*(lf: ptr NqLazyFrame, index: ptr NqExpr, by: ptr ptr NqExpr,
                                 nby: csize_t, every, period, offset: cstring, label: NqLabel,
                                 includeBoundaries: bool, closed: NqClosedWindow,
                                 startBy: NqStartBy, aggs: ptr ptr NqExpr,
                                 naggs: csize_t): ptr NqLazyFrame
proc nq_lf_rolling_agg*(lf: ptr NqLazyFrame, index: ptr NqExpr, by: ptr ptr NqExpr, nby: csize_t,
                        period, offset: cstring, closed: NqClosedWindow, aggs: ptr ptr NqExpr,
                        naggs: csize_t): ptr NqLazyFrame
proc nq_lf_join_asof*(left, right: ptr NqLazyFrame, leftOn, rightOn: ptr NqExpr,
                      byLeft: ptr cstring, nByLeft: csize_t, byRight: ptr cstring,
                      nByRight: csize_t, strategy: uint8, suffix: cstring, toleranceKind: uint8,
                      tolStr: cstring, tolInt: int64, tolFloat: cdouble,
                      allowExactMatches, checkSortedness, coalesce: bool): ptr NqLazyFrame
proc nq_df_get_column*(df: ptr NqDataFrame, name: cstring): ptr NqSeries
proc nq_df_to_series*(df: ptr NqDataFrame, idx: csize_t): ptr NqSeries
proc nq_series_to_frame*(s: ptr NqSeries): ptr NqDataFrame
proc nq_series_name*(s: ptr NqSeries): cstring
proc nq_series_len*(s: ptr NqSeries): csize_t
proc nq_series_rename*(s: ptr NqSeries, name: cstring): ptr NqSeries
proc nq_series_to_string*(s: ptr NqSeries): cstring
proc nq_lf_value_counts*(lf: ptr NqLazyFrame, e: ptr NqExpr, sort, normalize: bool,
                         name: cstring): ptr NqLazyFrame
proc nq_expr_alias*(e: ptr NqExpr, name: cstring): ptr NqExpr
proc nq_expr_cast*(e: ptr NqExpr, spec: ptr NqDtypeSpec, strict: bool): ptr NqExpr
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
proc nq_lf_sort_by*(lf: ptr NqLazyFrame, by: ptr ptr NqExpr, n: csize_t, descending: ptr bool,
                    nDesc: csize_t, nullsLast: ptr bool, nNulls: csize_t,
                    maintainOrder: bool): ptr NqLazyFrame
proc nq_lf_drop_nulls*(lf: ptr NqLazyFrame, names: ptr cstring, n: csize_t): ptr NqLazyFrame
proc nq_lf_limit*(lf: ptr NqLazyFrame, n: uint32): ptr NqLazyFrame
proc nq_lf_explain*(lf: ptr NqLazyFrame): cstring
proc nq_lf_collect_schema*(lf: ptr NqLazyFrame): ptr NqDataFrame
proc nq_lf_cast*(lf: ptr NqLazyFrame, names: ptr cstring, specs: ptr NqDtypeSpec, n: csize_t,
                 strict: bool): ptr NqLazyFrame
proc nq_lf_cast_all*(lf: ptr NqLazyFrame, spec: ptr NqDtypeSpec, strict: bool): ptr NqLazyFrame
proc nq_lf_join*(left, right: ptr NqLazyFrame, leftOn: ptr ptr NqExpr, nLeft: csize_t,
                 rightOn: ptr ptr NqExpr, nRight: csize_t, how: NqJoinType, suffix: cstring,
                 validate: NqJoinValidation, nullsEqual: bool, coalesce: int32,
                 maintainOrder: NqMaintainOrderJoin): ptr NqLazyFrame
proc nq_lf_concat*(lfs: ptr ptr NqLazyFrame, n: csize_t, how: NqConcat): ptr NqLazyFrame

# frame verbs
proc nq_lf_drop*(lf: ptr NqLazyFrame, names: ptr cstring, n: csize_t, strict: bool): ptr NqLazyFrame
proc nq_lf_rename*(lf: ptr NqLazyFrame, existing, new: ptr cstring, n: csize_t,
                   strict: bool): ptr NqLazyFrame
proc nq_lf_slice*(lf: ptr NqLazyFrame, offset: int64, len: uint32): ptr NqLazyFrame
proc nq_lf_reverse*(lf: ptr NqLazyFrame): ptr NqLazyFrame
proc nq_lf_with_row_index*(lf: ptr NqLazyFrame, name: cstring, offset: uint32): ptr NqLazyFrame
proc nq_lf_unique*(lf: ptr NqLazyFrame, subset: ptr cstring, n: csize_t,
                   keep: NqUniqueKeepStrategy, maintainOrder: bool): ptr NqLazyFrame
proc nq_df_sample*(df: ptr NqDataFrame, n: csize_t, fraction: float64, byFraction: bool,
                   withReplacement, shuffle, hasSeed: bool, seed: uint64): ptr NqDataFrame
proc nq_set_random_seed*(seed: uint64)

# more expressions
proc nq_expr_when_then*(conds, values: ptr ptr NqExpr, n: csize_t,
                        otherwise: ptr NqExpr): ptr NqExpr
proc nq_expr_lit_series*(s: ptr NqSeries): ptr NqExpr
proc nq_expr_lit_values*(s: ptr NqSeries): ptr NqExpr
proc nq_expr_is_in*(e, other: ptr NqExpr, nullsEqual: bool): ptr NqExpr
proc nq_expr_is_between*(e, lower, upper: ptr NqExpr, closed: NqClosedInterval): ptr NqExpr
proc nq_expr_quantile*(e: ptr NqExpr, q: float64, meth: NqQuantileMethod): ptr NqExpr
proc nq_expr_var_std*(e: ptr NqExpr, ddof: uint8, isVar: bool): ptr NqExpr
proc nq_expr_fill_null_strategy*(e: ptr NqExpr, strategy: NqFillNullStrategy, hasLimit: bool,
                                 limit: uint32): ptr NqExpr
proc nq_expr_round*(e: ptr NqExpr, decimals: uint32, mode: NqRoundMode): ptr NqExpr
proc nq_expr_over*(e: ptr NqExpr, by: ptr ptr NqExpr, n: csize_t): ptr NqExpr

# column selectors
proc nq_expr_selector*(names: ptr cstring, nNames: csize_t, dtypes: ptr NqDtypeSpec, nDtypes: csize_t,
                       classes: uint32, wildcard: bool, excluded: ptr cstring,
                       nExcluded: csize_t): ptr NqExpr
proc nq_expr_name_affix*(e: ptr NqExpr, affix: cstring, prefix: bool): ptr NqExpr

# strings
proc nq_expr_str*(e: ptr NqExpr, op: NqStrOp, a, b: ptr NqExpr, flag1, flag2: bool, n: int64,
                  ch: uint32, s: cstring): ptr NqExpr
proc nq_expr_concat_str*(es: ptr ptr NqExpr, n: csize_t, separator: cstring,
                         ignoreNulls: bool): ptr NqExpr

# temporal values
proc nq_df_column_time_unit*(df: ptr NqDataFrame, name: cstring): int32
proc nq_df_column_time_zone*(df: ptr NqDataFrame, name: cstring): cstring
proc nq_df_column_n_categories*(df: ptr NqDataFrame, name: cstring): int64
proc nq_df_column_category*(df: ptr NqDataFrame, name: cstring, i: csize_t): cstring
proc nq_series_cast*(s: ptr NqSeries, dtype: ptr NqDtypeSpec): ptr NqSeries
proc nq_expr_filter*(e, predicate: ptr NqExpr): ptr NqExpr
proc nq_expr_cat*(e: ptr NqExpr, op: NqCatOp, s: cstring, offset, length: int64): ptr NqExpr
proc nq_df_column_physical*(df: ptr NqDataFrame, name: cstring, output: ptr int64, valid: ptr bool,
                            n: csize_t): bool
proc nq_series_new_temporal*(name: cstring, values: ptr int64, valid: ptr bool, n: csize_t,
                             spec: ptr NqDtypeSpec): ptr NqSeries
proc nq_expr_lit_temporal*(v: int64, spec: ptr NqDtypeSpec): ptr NqExpr
proc nq_expr_to_physical*(e: ptr NqExpr): ptr NqExpr
proc nq_expr_date_range*(start, stop: ptr NqExpr, interval: cstring, closed: NqClosedWindow,
                         datetime, hasTimeUnit: bool, tu: NqTimeUnit, tz: cstring): ptr NqExpr
proc nq_expr_duration*(parts: ptr ptr NqExpr, tu: NqTimeUnit): ptr NqExpr
proc nq_expr_strptime*(e: ptr NqExpr, spec: ptr NqDtypeSpec, format: cstring,
                       strict, exact, cache: bool, ambiguous: cstring): ptr NqExpr
proc nq_expr_dt*(e: ptr NqExpr, op: NqDtOp, a: ptr NqExpr, s: cstring, flag: bool,
                 tu: NqTimeUnit, nonExistent: int32): ptr NqExpr

# ranking
proc nq_expr_rank*(e: ptr NqExpr, meth: NqRankMethod, descending, hasSeed: bool,
                   seed: uint64): ptr NqExpr

proc nq_expr_date*(year, month, day: ptr NqExpr): ptr NqExpr
proc nq_lf_top_k*(lf: ptr NqLazyFrame, k: csize_t, by: ptr ptr NqExpr, nby: csize_t,
                  reverse, bottom: bool): ptr NqLazyFrame
proc nq_set_float_precision*(n: int32)
proc nq_get_float_precision*(): int32
proc nq_expr_lit_null*(): ptr NqExpr
proc nq_expr_any_all*(e: ptr NqExpr, all, ignoreNulls: bool): ptr NqExpr

# data type handles and nested Series (0.5)
proc nq_dtype_free*(d: ptr NqDataType)
proc nq_df_column_dtype_handle*(df: ptr NqDataFrame, name: cstring): ptr NqDataType
proc nq_dtype_from_spec*(spec: ptr NqDtypeSpec): ptr NqDataType
proc nq_dtype_list*(inner: ptr NqDataType): ptr NqDataType
proc nq_dtype_array*(inner: ptr NqDataType, width: csize_t): ptr NqDataType
proc nq_dtype_struct*(names: ptr cstring, dtypes: ptr ptr NqDataType, n: csize_t): ptr NqDataType
proc nq_dtype_kind*(d: ptr NqDataType): int32
proc nq_dtype_name*(d: ptr NqDataType): cstring
proc nq_dtype_time_unit*(d: ptr NqDataType): int32
proc nq_dtype_time_zone*(d: ptr NqDataType): cstring
proc nq_dtype_n_categories*(d: ptr NqDataType): int64
proc nq_dtype_category*(d: ptr NqDataType, i: csize_t): cstring
proc nq_dtype_inner*(d: ptr NqDataType): ptr NqDataType
proc nq_dtype_width*(d: ptr NqDataType): int64
proc nq_dtype_n_fields*(d: ptr NqDataType): int64
proc nq_dtype_field_name*(d: ptr NqDataType, i: csize_t): cstring
proc nq_dtype_field*(d: ptr NqDataType, i: csize_t): ptr NqDataType
proc nq_series_list_from_parts*(name: cstring, inner: ptr NqSeries, offsets: ptr int64,
                                valid: ptr bool, n: csize_t): ptr NqSeries
proc nq_series_struct_from_fields*(name: cstring, fields: ptr ptr NqSeries, nFields: csize_t,
                                   valid: ptr bool, n: csize_t): ptr NqSeries
proc nq_series_validity*(s: ptr NqSeries, outp: ptr bool, n: csize_t): bool
proc nq_series_list_offsets*(s: ptr NqSeries, outp: ptr int64, n: csize_t): bool
proc nq_series_inner*(s: ptr NqSeries): ptr NqSeries
proc nq_series_n_fields*(s: ptr NqSeries): int64
proc nq_series_struct_field*(s: ptr NqSeries, i: csize_t): ptr NqSeries

# list namespace, explode, implode (0.5)
proc nq_expr_list*(e: ptr NqExpr, op: NqListOp, a, b: ptr NqExpr, f1, f2, f3: bool, n: int64,
                   seed: int64, names: ptr cstring, nNames: csize_t): ptr NqExpr
proc nq_expr_implode*(e: ptr NqExpr): ptr NqExpr
proc nq_concat_list*(es: ptr ptr NqExpr, n: csize_t): ptr NqExpr
proc nq_lf_explode*(lf: ptr NqLazyFrame, names: ptr cstring, n: csize_t,
                    emptyAsNull, keepNulls: bool): ptr NqLazyFrame
proc nq_expr_str_nested*(e: ptr NqExpr, op: NqStrNestedOp, a, b: ptr NqExpr, f1, f2, f3: bool,
                         n: csize_t, pat: cstring, spec: ptr NqDtypeSpec): ptr NqExpr
proc nq_as_struct*(es: ptr ptr NqExpr, n: csize_t): ptr NqExpr
proc nq_expr_struct*(e: ptr NqExpr, op: NqStructOp, names: ptr cstring, nNames: csize_t,
                     es: ptr ptr NqExpr, nEs: csize_t, index: int64): ptr NqExpr
proc nq_expr_value_counts*(e: ptr NqExpr, sort, parallel: bool, name: cstring,
                           normalize: bool): ptr NqExpr
proc nq_lf_unnest*(lf: ptr NqLazyFrame, names: ptr cstring, n: csize_t,
                   separator: cstring): ptr NqLazyFrame
proc nq_expr_arr*(e: ptr NqExpr, op: NqArrOp, a, b: ptr NqExpr, f1, f2: bool,
                  n: int64): ptr NqExpr
{.pop.}

let compiledFor = nanuqLibVersion
if $nq_version() != compiledFor:
  raise newException(Defect, "nanuq: the linked Polars wrapper library is version " &
    $nq_version() & " but these bindings were compiled for " & compiledFor &
    ". Rebuild it or point -d:nanuqLibDir at a matching library.")
