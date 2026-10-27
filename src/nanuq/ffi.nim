## Raw bindings to the `nanuq_ffi` Rust crate (see `rust/src/lib.rs`).
##
## This mirrors the C ABI one to one, in the style of an
## `nbindgen <https://github.com/arnetheduck/nbindgen>`_ generated header.
## You normally want the high level API in `nanuq` instead.
##
## Linking: by default the static library is taken from
## `rust/target/release/libnanuq_ffi.a` next to this package, and is built with
## `cargo` at compile time if missing. Define `-d:nanuqLibDir=/some/dir` to use
## a prebuilt library from elsewhere, or `-d:nanuqNoCargo` to never run cargo.

import std/os

const
  nanuqRoot = currentSourcePath.parentDir.parentDir.parentDir
  rustDir = nanuqRoot / "rust"
  nanuqLibDir {.strdefine.} = rustDir / "target" / "release"
  libFile = nanuqLibDir / "libnanuq_ffi.a"

when not defined(nanuqNoCargo) and not fileExists(libFile):
  {.hint: "nanuq: building Polars wrapper with cargo, the first build takes a few minutes...".}
  const cargoOut = gorgeEx("cargo build --release --manifest-path " &
                           quoteShell(rustDir / "Cargo.toml"))
  when cargoOut.exitCode != 0:
    {.error: "nanuq: cargo build failed:\n" & cargoOut.output.}

when not fileExists(libFile):
  {.error: "nanuq: cannot find " & libFile & ", run `nimble buildRust` first.".}

{.passL: quoteShell(libFile).}
when defined(linux):
  {.passL: "-lpthread -ldl -lm".}
elif defined(macosx):
  {.passL: "-framework CoreFoundation -framework Security -lc++".}

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
    nqFirst, nqLast, nqNUnique, nqStd

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

# dataframe
proc nq_df_free*(df: ptr NqDataFrame)
proc nq_df_new*(series: ptr ptr NqSeries, n: csize_t): ptr NqDataFrame
proc nq_df_read_csv*(path: cstring): ptr NqDataFrame
proc nq_df_write_csv*(df: ptr NqDataFrame, path: cstring): bool
proc nq_df_height*(df: ptr NqDataFrame): int64
proc nq_df_width*(df: ptr NqDataFrame): int64
proc nq_df_to_string*(df: ptr NqDataFrame): cstring
proc nq_df_head*(df: ptr NqDataFrame, n: csize_t): ptr NqDataFrame
proc nq_df_column_name*(df: ptr NqDataFrame, idx: csize_t): cstring
proc nq_df_column_dtype*(df: ptr NqDataFrame, name: cstring): cstring
proc nq_df_get_i64*(df: ptr NqDataFrame, name: cstring, row: csize_t, output: ptr int64): bool
proc nq_df_get_f64*(df: ptr NqDataFrame, name: cstring, row: csize_t, output: ptr float64): bool
proc nq_df_get_str*(df: ptr NqDataFrame, name: cstring, row: csize_t): cstring

# expressions
proc nq_expr_free*(e: ptr NqExpr)
proc nq_expr_col*(name: cstring): ptr NqExpr
proc nq_expr_lit_i64*(v: int64): ptr NqExpr
proc nq_expr_lit_f64*(v: float64): ptr NqExpr
proc nq_expr_lit_bool*(v: bool): ptr NqExpr
proc nq_expr_lit_str*(v: cstring): ptr NqExpr
proc nq_expr_binary*(a: ptr NqExpr, op: NqBinOp, b: ptr NqExpr): ptr NqExpr
proc nq_expr_unary*(e: ptr NqExpr, op: NqUnary): ptr NqExpr
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
proc nq_lf_limit*(lf: ptr NqLazyFrame, n: uint32): ptr NqLazyFrame
proc nq_lf_explain*(lf: ptr NqLazyFrame): cstring

{.pop.}
