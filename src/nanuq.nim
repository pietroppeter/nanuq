## Nanuq: Polars DataFrames for Nim.
##
## Nanuq wraps the Rust `Polars <https://pola.rs>`_ library through a small C
## ABI (the `nanuq_ffi` crate in `src/rust/`). Polars objects are owned by Rust and
## released automatically when the Nim value goes out of scope.
##
## .. code-block:: nim
##   import nanuq, nanuq/datasets
##
##   let df = penguins()  # or readCsv("penguins.csv", nullValues = ["NA"])
##   echo df.lazy
##     .filter(col("bill_length_mm") > 40.0)
##     .groupBy(col("species"))
##     .agg(col("bill_depth_mm").mean.alias("mean_depth"), col("species").count.alias("n"))
##     .sort("species")
##     .collect
##
## Missing values (Polars nulls) are read as `Option[T]`:
##
## .. code-block:: nim
##   let df = newDataFrame(series("a", [some(1), none(int), some(3)]))
##   echo df.toSeq("a", Option[int])   # @[some(1), none(int), some(3)]
##   echo df.nullCount("a")            # 1
##   df.toSeq("a", int)                # raises NanuqError: column has nulls

import std/[options, tables]
import nanuq/ffi

export options  # some/none/Option, for null-aware reads and series
export tables   # Schema is an OrderedTable
export nanuqLibVersion  # version of the Rust wrapper crate these bindings expect

type
  NanuqError* = object of CatchableError

  DataFrameObj = object
    raw: ptr NqDataFrame
  LazyFrameObj = object
    raw: ptr NqLazyFrame
  ExprObj = object
    raw: ptr NqExpr
  SeriesObj = object
    raw: ptr NqSeries

  DataFrame* = ref DataFrameObj
    ## An eager, materialized table.
  LazyFrame* = ref LazyFrameObj
    ## A query plan, executed by `collect`.
  Expr* = ref ExprObj
    ## A column expression such as `col("a") + 1`.
  Series* = ref SeriesObj
    ## A named column, used to build a DataFrame.

  LazyGroupBy* = object
    lf: LazyFrame
    by: seq[Expr]

# Polars objects are immutable from Nim's point of view, so values are shared
# refs and the Rust object is freed when the last ref goes away.
proc `=destroy`(x: DataFrameObj) =
  if x.raw != nil: nq_df_free(x.raw)
proc `=destroy`(x: LazyFrameObj) =
  if x.raw != nil: nq_lf_free(x.raw)
proc `=destroy`(x: ExprObj) =
  if x.raw != nil: nq_expr_free(x.raw)
proc `=destroy`(x: SeriesObj) =
  if x.raw != nil: nq_series_free(x.raw)

proc `=copy`(a: var DataFrameObj, b: DataFrameObj) {.error.}
proc `=copy`(a: var LazyFrameObj, b: LazyFrameObj) {.error.}
proc `=copy`(a: var ExprObj, b: ExprObj) {.error.}
proc `=copy`(a: var SeriesObj, b: SeriesObj) {.error.}

proc raiseLast() {.noreturn.} =
  let msg = nq_last_error()
  raise newException(NanuqError, if msg == nil: "unknown nanuq error" else: $msg)

template check[T](p: ptr T): ptr T =
  let r = p
  if r == nil: raiseLast()
  r

proc wrap(p: ptr NqDataFrame): DataFrame = DataFrame(raw: check p)
proc wrap(p: ptr NqLazyFrame): LazyFrame = LazyFrame(raw: check p)
proc wrap(p: ptr NqExpr): Expr = Expr(raw: check p)
proc wrap(p: ptr NqSeries): Series = Series(raw: check p)

proc takeString(s: cstring): string =
  ## Copies a Rust owned string into Nim and frees it.
  if s == nil: raiseLast()
  result = $s
  nq_string_free(s)

proc raws(xs: openArray[Expr]): seq[ptr NqExpr] =
  for x in xs: result.add x.raw

template firstOrNil[T](s: seq[T]): ptr T =
  (if s.len == 0: nil else: s[0].unsafeAddr)

proc polarsWrapperVersion*(): string =
  ## Version of the Rust wrapper crate.
  $nq_version()

# ---------------------------------------------------------------------------
# Data types
# ---------------------------------------------------------------------------

type
  DataTypeKind* = enum
    ## Same order as `NqDtype` in the C ABI.
    dkBoolean, dkInt8, dkInt16, dkInt32, dkInt64, dkUInt8, dkUInt16, dkUInt32,
    dkUInt64, dkFloat32, dkFloat64, dkString, dkNull, dkOther

  DataType* = object
    ## A Polars data type. Compare with the constants (`Int64`, `String`, ...).
    ## Dtypes Nanuq does not model yet (dates, lists, ...) have kind `dkOther`
    ## and keep Polars' name.
    case kind*: DataTypeKind
    of dkOther: name*: string
    else: discard

  Schema* = OrderedTable[string, DataType]
    ## Column names and data types, in column order.

const
  Boolean* = DataType(kind: dkBoolean)
  Int8* = DataType(kind: dkInt8)
  Int16* = DataType(kind: dkInt16)
  Int32* = DataType(kind: dkInt32)
  Int64* = DataType(kind: dkInt64)
  UInt8* = DataType(kind: dkUInt8)
  UInt16* = DataType(kind: dkUInt16)
  UInt32* = DataType(kind: dkUInt32)
  UInt64* = DataType(kind: dkUInt64)
  Float32* = DataType(kind: dkFloat32)
  Float64* = DataType(kind: dkFloat64)
  String* = DataType(kind: dkString)
  Null* = DataType(kind: dkNull)

proc `==`*(a, b: DataType): bool =
  a.kind == b.kind and (a.kind != dkOther or a.name == b.name)

proc `$`*(t: DataType): string =
  ## Polars' short name, e.g. "i64", "str".
  case t.kind
  of dkBoolean: "bool"
  of dkInt8: "i8"
  of dkInt16: "i16"
  of dkInt32: "i32"
  of dkInt64: "i64"
  of dkUInt8: "u8"
  of dkUInt16: "u16"
  of dkUInt32: "u32"
  of dkUInt64: "u64"
  of dkFloat32: "f32"
  of dkFloat64: "f64"
  of dkString: "str"
  of dkNull: "null"
  of dkOther: t.name

proc isSignedInteger*(t: DataType): bool = t.kind in {dkInt8 .. dkInt64}
proc isUnsignedInteger*(t: DataType): bool = t.kind in {dkUInt8 .. dkUInt64}
proc isInteger*(t: DataType): bool = t.isSignedInteger or t.isUnsignedInteger
proc isFloat*(t: DataType): bool = t.kind in {dkFloat32, dkFloat64}
proc isNumeric*(t: DataType): bool = t.isInteger or t.isFloat

proc dataType*(T: typedesc): DataType =
  ## The data type of a Nim type: `int8` .. `int64`, `uint8` .. `uint64`,
  ## `float32`, `float64`, `bool`, `string`. `int` and `float` give `Int64`
  ## and `Float64`, as `series` builds them. Other types do not compile.
  when T is int8: Int8
  elif T is int16: Int16
  elif T is int32: Int32
  elif T is int64 or T is int: Int64
  elif T is uint8: UInt8
  elif T is uint16: UInt16
  elif T is uint32: UInt32
  elif T is uint64: UInt64
  elif T is float32: Float32
  elif T is float64: Float64
  elif T is bool: Boolean
  elif T is string: String
  else: {.error: "nanuq: no Polars data type for " & $T.}

proc code(t: DataType): NqDtype =
  if t.kind == dkOther:
    raise newException(NanuqError, "cannot cast to " & t.name & ": Nanuq does not model this dtype yet")
  NqDtype(ord(t.kind))

# ---------------------------------------------------------------------------
# Series and DataFrame construction
# ---------------------------------------------------------------------------

proc series*(name: string, data: openArray[int]): Series =
  var buf = newSeq[int64](data.len)
  for i, x in data: buf[i] = x.int64
  wrap nq_series_new_i64(name.cstring, buf.firstOrNil, buf.len.csize_t)

proc series*(name: string, data: openArray[float]): Series =
  let buf = @data
  wrap nq_series_new_f64(name.cstring, buf.firstOrNil, buf.len.csize_t)

proc series*(name: string, data: openArray[bool]): Series =
  let buf = @data
  wrap nq_series_new_bool(name.cstring, buf.firstOrNil, buf.len.csize_t)

proc series*(name: string, data: openArray[string]): Series =
  var buf = newSeq[cstring](data.len)
  for i, x in data: buf[i] = x.cstring
  wrap nq_series_new_str(name.cstring, buf.firstOrNil, buf.len.csize_t)

proc optBuffers[T, B](data: openArray[Option[T]], conv: proc (x: T): B): (seq[B], seq[bool]) =
  result = (newSeq[B](data.len), newSeq[bool](data.len))
  for i, x in data:
    if x.isSome:
      result[0][i] = conv(x.get)
      result[1][i] = true

proc series*(name: string, data: openArray[Option[int]]): Series =
  ## A column with nulls where `data` is `none`.
  let (buf, valid) = optBuffers(data, proc (x: int): int64 = x.int64)
  wrap nq_series_new_i64_opt(name.cstring, buf.firstOrNil, valid.firstOrNil, buf.len.csize_t)

proc series*(name: string, data: openArray[Option[float]]): Series =
  let (buf, valid) = optBuffers(data, proc (x: float): float64 = x)
  wrap nq_series_new_f64_opt(name.cstring, buf.firstOrNil, valid.firstOrNil, buf.len.csize_t)

proc series*(name: string, data: openArray[Option[bool]]): Series =
  let (buf, valid) = optBuffers(data, proc (x: bool): bool = x)
  wrap nq_series_new_bool_opt(name.cstring, buf.firstOrNil, valid.firstOrNil, buf.len.csize_t)

proc series*(name: string, data: openArray[Option[string]]): Series =
  var buf = newSeq[cstring](data.len)
  var valid = newSeq[bool](data.len)
  for i, x in data:
    if x.isSome:
      buf[i] = x.get.cstring   # data stays alive for the call
      valid[i] = true
  wrap nq_series_new_str_opt(name.cstring, buf.firstOrNil, valid.firstOrNil, buf.len.csize_t)

proc newDataFrame*(columns: varargs[Series]): DataFrame =
  ## Builds a DataFrame from columns of equal length.
  ##
  ## .. code-block:: nim
  ##   let df = newDataFrame(series("a", [1, 2, 3]), series("b", ["x", "y", "z"]))
  var buf = newSeq[ptr NqSeries](columns.len)
  for i, c in columns: buf[i] = c.raw
  wrap nq_df_new(buf.firstOrNil, buf.len.csize_t)

proc readCsv*(path: string, nullValues: openArray[string] = []): DataFrame =
  ## Reads a CSV file with a header row. Fields equal to one of `nullValues`
  ## (e.g. `["NA"]`) are read as null; empty fields always are.
  var nulls = newSeq[cstring](nullValues.len)
  for i, v in nullValues: nulls[i] = v.cstring
  wrap nq_df_read_csv(path.cstring, nulls.firstOrNil, nulls.len.csize_t)

proc writeCsv*(df: DataFrame, path: string) =
  if not nq_df_write_csv(df.raw, path.cstring): raiseLast()

# ---------------------------------------------------------------------------
# DataFrame inspection
# ---------------------------------------------------------------------------

proc height*(df: DataFrame): int = nq_df_height(df.raw).int
proc width*(df: DataFrame): int = nq_df_width(df.raw).int
proc len*(df: DataFrame): int = df.height
  ## Number of rows.
proc shape*(df: DataFrame): (int, int) = (df.height, df.width)

proc `$`*(df: DataFrame): string = takeString nq_df_to_string(df.raw)

proc head*(df: DataFrame, n = 5): DataFrame = wrap nq_df_head(df.raw, n.csize_t)

proc columns*(df: DataFrame): seq[string] =
  for i in 0 ..< df.width:
    result.add takeString nq_df_column_name(df.raw, i.csize_t)

proc dtype*(df: DataFrame, column: string): DataType =
  ## Data type of a column, e.g. `Int64`; `$` gives Polars' name ("i64").
  let k = nq_df_column_dtype_kind(df.raw, column.cstring)
  if k < 0: raiseLast()
  if k == ord(dkOther):
    DataType(kind: dkOther, name: takeString nq_df_column_dtype(df.raw, column.cstring))
  else:
    DataType(kind: DataTypeKind(k))

proc dtypes*(df: DataFrame): seq[DataType] =
  ## Data types of all columns, in order.
  for name in df.columns: result.add df.dtype(name)

proc schema*(df: DataFrame): Schema =
  ## Column names and data types, in column order.
  for name in df.columns: result[name] = df.dtype(name)

proc getInt*(df: DataFrame, column: string, row: int): int =
  ## Raises `NanuqError` if the cell is null; see `df[column, row, Option[int]]`.
  var v: int64
  if not nq_df_get_i64(df.raw, column.cstring, row.csize_t, v.addr): raiseLast()
  v.int

proc getFloat*(df: DataFrame, column: string, row: int): float =
  if not nq_df_get_f64(df.raw, column.cstring, row.csize_t, result.addr): raiseLast()

proc getBool*(df: DataFrame, column: string, row: int): bool =
  if not nq_df_get_bool(df.raw, column.cstring, row.csize_t, result.addr): raiseLast()

proc getStr*(df: DataFrame, column: string, row: int): string =
  takeString nq_df_get_str(df.raw, column.cstring, row.csize_t)

proc `[]`*(df: DataFrame, column: string, row: int, T: typedesc[int]): int = df.getInt(column, row)
proc `[]`*(df: DataFrame, column: string, row: int, T: typedesc[float]): float = df.getFloat(column, row)
proc `[]`*(df: DataFrame, column: string, row: int, T: typedesc[bool]): bool = df.getBool(column, row)
proc `[]`*(df: DataFrame, column: string, row: int, T: typedesc[string]): string = df.getStr(column, row)

proc `[]`*[T: int | float | bool | string](df: DataFrame, column: string, row: int,
                                           _: typedesc[Option[T]]): Option[T] =
  ## One cell, `none` if it is null.
  var isNull: bool
  if not nq_df_cell_is_null(df.raw, column.cstring, row.csize_t, isNull.addr): raiseLast()
  if not isNull: result = some(df[column, row, T])

proc nullCount*(df: DataFrame, column: string): int =
  ## Number of nulls in a column.
  result = nq_df_null_count(df.raw, column.cstring).int
  if result < 0: raiseLast()

proc hasNulls*(df: DataFrame, column: string): bool = df.nullCount(column) > 0

# ---------------------------------------------------------------------------
# HTML tables, ported from Python Polars' `DataFrame._repr_html_`
# (py-polars/src/polars/dataframe/_html.py)

proc htmlEscape(s: string): string =
  ## Like Python's `html.escape(s, quote=True)`.
  for c in s:
    case c
    of '&': result.add "&amp;"
    of '<': result.add "&lt;"
    of '>': result.add "&gt;"
    of '"': result.add "&quot;"
    of '\'': result.add "&#x27;"
    else: result.add c

proc nbspRuns(s: string): string =
  ## Replaces runs of two or more spaces with as many `&nbsp;`.
  var i = 0
  while i < s.len:
    var j = i
    while j < s.len and s[j] == ' ': inc j
    if j - i >= 2:
      for _ in i ..< j: result.add "&nbsp;"
      i = j
    elif j > i:
      result.add ' '
      i = j
    else:
      result.add s[i]
      inc i

proc thousands(n: int): string =
  ## `n` with `_` thousand separators, like Python's `f"{n:_}"`.
  let digits = $n
  for i, c in digits:
    if i > 0 and (digits.len - i) mod 3 == 0: result.add '_'
    result.add c

proc indices(n, limit: int, isRows: bool): seq[int] =
  ## Indices to show, with -1 for the elided middle.
  if limit >= n:
    for i in 0 ..< n: result.add i
  else:
    let half = limit div 2
    let first = if isRows: half + limit mod 2 else: half
    for i in 0 ..< first: result.add i
    result.add -1
    for i in n - half ..< n: result.add i

proc cellFmt(df: DataFrame, column: string, row: int, strLen = 30): string =
  takeString nq_df_cell_fmt(df.raw, column.cstring, row.csize_t, strLen.csize_t)

proc toHtml*(df: DataFrame, maxRows = 10, maxCols = 75): string =
  ## The HTML table Python Polars shows in notebooks (`_repr_html_`): shape,
  ## column names and dtypes, and cells formatted by Polars. Beyond `maxRows`
  ## rows or `maxCols` columns, the first and last ones are shown around `…`.
  ## In nimib: `nbRawHtml: df.toHtml`.
  let names = df.columns
  let rows = indices(df.height, maxRows, isRows = true)
  let cols = indices(df.width, maxCols, isRows = false)
  result = "<div><style>\n.dataframe > thead > tr,\n.dataframe > tbody > tr {\n" &
    "  text-align: right;\n  white-space: pre-wrap;\n}\n</style>\n"
  result.add "<small>shape: (" & thousands(df.height) & ", " & thousands(df.width) & ")</small>"
  result.add "<table border=\"1\" class=\"dataframe\"><thead><tr>"
  for c in cols:
    result.add "<th>" & (if c == -1: "&hellip;" else: htmlEscape(names[c])) & "</th>"
  result.add "</tr><tr>"
  for c in cols:
    result.add "<td>" & (if c == -1: "&hellip;" else: $df.dtype(names[c])) & "</td>"
  result.add "</tr></thead><tbody>"
  for r in rows:
    result.add "<tr>"
    for c in cols:
      result.add "<td>"
      if r == -1 or c == -1: result.add "&hellip;"
      else: result.add nbspRuns(htmlEscape(df.cellFmt(names[c], r)))
      result.add "</td>"
    result.add "</tr>"
  result.add "</tbody></table></div>"

proc readColumn[T](df: DataFrame, column: string, _: typedesc[T]): (seq[T], seq[bool]) =
  ## Values and validity mask of a whole column, in one FFI call (two for strings).
  let n = df.height
  var valid = newSeq[bool](n)
  when T is int:
    var buf = newSeq[int64](n)
    if not nq_df_column_i64(df.raw, column.cstring, buf.firstOrNil, valid.firstOrNil, n.csize_t):
      raiseLast()
    var vals = newSeq[int](n)
    for i, x in buf: vals[i] = x.int
    (vals, valid)
  elif T is float:
    var vals = newSeq[float](n)
    if not nq_df_column_f64(df.raw, column.cstring, vals.firstOrNil, valid.firstOrNil, n.csize_t):
      raiseLast()
    (vals, valid)
  elif T is bool:
    var vals = newSeq[bool](n)
    if not nq_df_column_bool(df.raw, column.cstring, vals.firstOrNil, valid.firstOrNil, n.csize_t):
      raiseLast()
    (vals, valid)
  else:
    let size = nq_df_column_str_size(df.raw, column.cstring)
    if size < 0: raiseLast()
    var data = newSeq[uint8](size)
    var offsets = newSeq[uint64](n + 1)
    if not nq_df_column_str(df.raw, column.cstring, data.firstOrNil, size.csize_t,
                            offsets.firstOrNil, valid.firstOrNil, n.csize_t):
      raiseLast()
    var vals = newSeq[string](n)
    for i in 0 ..< n:
      let (a, b) = (offsets[i].int, offsets[i + 1].int)
      vals[i] = newString(b - a)
      if b > a: copyMem(vals[i][0].addr, data[a].addr, b - a)
    (vals, valid)

proc toSeq*[T: int | float | bool | string](df: DataFrame, column: string, _: typedesc[T]): seq[T] =
  ## Copies a whole column into a Nim seq. Raises `NanuqError` if the column has
  ## nulls: read it as `Option[T]`, or `fillNull` first.
  ##
  ## `float` reads integer columns too, `string` reads any column; `int` and
  ## `bool` only read their own types.
  let (vals, valid) = readColumn(df, column, T)
  var nulls = 0
  for ok in valid:
    if not ok: inc nulls
  if nulls > 0:
    raise newException(NanuqError, "column '" & column & "' has " & $nulls &
      " null(s); read it as Option[" & $T & "] or fill them first")
  vals

proc toSeq*[T: int | float | bool | string](df: DataFrame, column: string,
                                            _: typedesc[Option[T]]): seq[Option[T]] =
  ## Copies a whole column into a Nim seq, with `none` for nulls.
  let (vals, valid) = readColumn(df, column, T)
  result = newSeq[Option[T]](vals.len)
  for i, v in vals:
    if valid[i]: result[i] = some(v)

# ---------------------------------------------------------------------------
# Expressions
# ---------------------------------------------------------------------------

proc col*(name: string): Expr = wrap nq_expr_col(name.cstring)

proc lit*(v: int): Expr = wrap nq_expr_lit_i64(v.int64)
proc lit*(v: float): Expr = wrap nq_expr_lit_f64(v)
proc lit*(v: bool): Expr = wrap nq_expr_lit_bool(v)
proc lit*(v: string): Expr = wrap nq_expr_lit_str(v.cstring)
proc lit*(v: Expr): Expr = v

proc `$`*(e: Expr): string = takeString nq_expr_to_string(e.raw)

proc binary(a: Expr, op: NqBinOp, b: Expr): Expr = wrap nq_expr_binary(a.raw, op, b.raw)

template defBinOp(name, op) =
  proc name*(a, b: Expr): Expr = binary(a, op, b)
  proc name*[T: SomeNumber | string | bool](a: Expr, b: T): Expr = binary(a, op, lit(b))
  proc name*[T: SomeNumber | string | bool](a: T, b: Expr): Expr = binary(lit(a), op, b)

defBinOp(`+`, nqAdd)
defBinOp(`-`, nqSub)
defBinOp(`*`, nqMul)
defBinOp(`/`, nqDiv)
defBinOp(`==`, nqEq)
defBinOp(`!=`, nqNotEq)
defBinOp(`<`, nqLt)
defBinOp(`<=`, nqLtEq)
defBinOp(`>`, nqGt)
defBinOp(`>=`, nqGtEq)
defBinOp(`and`, nqAnd)
defBinOp(`or`, nqOr)

proc unary(e: Expr, op: NqUnary): Expr = wrap nq_expr_unary(e.raw, op)

proc `not`*(e: Expr): Expr = unary(e, nqNot)
proc sum*(e: Expr): Expr = unary(e, nqSum)
proc mean*(e: Expr): Expr = unary(e, nqMean)
proc min*(e: Expr): Expr = unary(e, nqMin)
proc max*(e: Expr): Expr = unary(e, nqMax)
proc count*(e: Expr): Expr = unary(e, nqCount)
proc first*(e: Expr): Expr = unary(e, nqFirst)
proc last*(e: Expr): Expr = unary(e, nqLast)
proc nUnique*(e: Expr): Expr = unary(e, nqNUnique)
proc std*(e: Expr): Expr = unary(e, nqStd)
  ## Sample standard deviation (ddof = 1).

proc isNull*(e: Expr): Expr = unary(e, nqIsNull)
proc isNotNull*(e: Expr): Expr = unary(e, nqIsNotNull)

proc fillNull*(e: Expr, value: Expr): Expr =
  ## Replaces nulls with `value` (an expression, or a literal below).
  wrap nq_expr_fill_null(e.raw, value.raw)
proc fillNull*[T: SomeNumber | string | bool](e: Expr, value: T): Expr = e.fillNull(lit(value))

proc alias*(e: Expr, name: string): Expr = wrap nq_expr_alias(e.raw, name.cstring)

proc `cast`*(e: Expr, dtype: DataType, strict = true): Expr =
  ## Converts to `dtype`. A strict cast fails (when the query runs) on values
  ## that can't be converted; with `strict = false` they become nulls.
  ## `cast` is a Nim keyword: write `e.cast(Int32)`, or `` `cast`(e, Int32) ``.
  wrap nq_expr_cast(e.raw, dtype.code, strict)

proc `cast`*(e: Expr, T: typedesc, strict = true): Expr =
  ## Converts to the data type of a Nim type: `col("a").cast(int32)`.
  e.cast(dataType(T), strict)

# ---------------------------------------------------------------------------
# Lazy API
# ---------------------------------------------------------------------------

proc lazy*(df: DataFrame): LazyFrame = wrap nq_df_lazy(df.raw)

proc collect*(lf: LazyFrame): DataFrame = wrap nq_lf_collect(lf.raw)

proc select*(lf: LazyFrame, exprs: varargs[Expr]): LazyFrame =
  let r = raws(exprs)
  wrap nq_lf_select(lf.raw, r.firstOrNil, r.len.csize_t)

proc withColumns*(lf: LazyFrame, exprs: varargs[Expr]): LazyFrame =
  let r = raws(exprs)
  wrap nq_lf_with_columns(lf.raw, r.firstOrNil, r.len.csize_t)

proc filter*(lf: LazyFrame, predicate: Expr): LazyFrame =
  wrap nq_lf_filter(lf.raw, predicate.raw)

proc groupBy*(lf: LazyFrame, by: varargs[Expr]): LazyGroupBy =
  ## Group rows (keeping first-seen group order); follow with `agg`.
  LazyGroupBy(lf: lf, by: @by)

proc agg*(g: LazyGroupBy, aggs: varargs[Expr]): LazyFrame =
  let b = raws(g.by)
  let a = raws(aggs)
  wrap nq_lf_group_by_agg(g.lf.raw, b.firstOrNil, b.len.csize_t, a.firstOrNil, a.len.csize_t)

proc sort*(lf: LazyFrame, by: string, descending = false): LazyFrame =
  wrap nq_lf_sort(lf.raw, by.cstring, descending)

proc dropNulls*(lf: LazyFrame, subset: varargs[string]): LazyFrame =
  ## Drops rows with a null in any column, or only in the `subset` columns.
  var names = newSeq[cstring](subset.len)
  for i, s in subset: names[i] = s.cstring
  wrap nq_lf_drop_nulls(lf.raw, names.firstOrNil, names.len.csize_t)

proc collectSchema*(lf: LazyFrame): Schema =
  ## The schema of the result, without running the query.
  schema(wrap nq_lf_collect_schema(lf.raw))

proc `cast`*(lf: LazyFrame, dtypes: openArray[(string, DataType)], strict = true): LazyFrame =
  ## Casts the named columns: `lf.cast({"a": Int32, "b": Float32})`.
  var names = newSeq[cstring](dtypes.len)
  var codes = newSeq[NqDtype](dtypes.len)
  for i, (name, t) in dtypes:
    names[i] = name.cstring
    codes[i] = t.code
  wrap nq_lf_cast(lf.raw, names.firstOrNil, codes.firstOrNil, names.len.csize_t, strict)

proc `cast`*(lf: LazyFrame, dtype: DataType, strict = true): LazyFrame =
  ## Casts every column to `dtype`.
  wrap nq_lf_cast_all(lf.raw, dtype.code, strict)

proc `cast`*(lf: LazyFrame, T: typedesc, strict = true): LazyFrame =
  ## Casts every column to the data type of a Nim type: `lf.cast(float64)`.
  lf.cast(dataType(T), strict)

proc limit*(lf: LazyFrame, n: int): LazyFrame = wrap nq_lf_limit(lf.raw, n.uint32)

proc explain*(lf: LazyFrame): string =
  ## The optimized query plan.
  takeString nq_lf_explain(lf.raw)

# Eager shortcuts: run a single lazy step and collect.
proc select*(df: DataFrame, exprs: varargs[Expr]): DataFrame = df.lazy.select(exprs).collect
proc withColumns*(df: DataFrame, exprs: varargs[Expr]): DataFrame = df.lazy.withColumns(exprs).collect
proc filter*(df: DataFrame, predicate: Expr): DataFrame = df.lazy.filter(predicate).collect
proc sort*(df: DataFrame, by: string, descending = false): DataFrame = df.lazy.sort(by, descending).collect
proc groupBy*(df: DataFrame, by: varargs[Expr]): LazyGroupBy = df.lazy.groupBy(by)
proc dropNulls*(df: DataFrame, subset: varargs[string]): DataFrame = df.lazy.dropNulls(subset).collect
proc `cast`*(df: DataFrame, dtypes: openArray[(string, DataType)], strict = true): DataFrame =
  df.lazy.cast(dtypes, strict).collect
proc `cast`*(df: DataFrame, dtype: DataType, strict = true): DataFrame = df.lazy.cast(dtype, strict).collect
proc `cast`*(df: DataFrame, T: typedesc, strict = true): DataFrame = df.lazy.cast(T, strict).collect
