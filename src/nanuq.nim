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
##   echo df.toList("a", Option[int])  # @[some(1), none(int), some(3)]
##   echo df.nullCount("a")            # 1
##   df.toList("a", int)               # raises InvalidOperationError: column has nulls

{.experimental: "callOperator".}   # `col("a")` on the `col` constant
{.experimental: "dotOperators".}   # `col.a`

import std/[macros, options, tables, os, strutils, math]
from std/unicode import runeLen, runeSubStr
import nanuq/ffi

export options  # some/none/Option, for null-aware reads and series
export tables   # Schema is an OrderedTable
export nanuqLibVersion  # version of the Rust wrapper crate these bindings expect

type
  PolarsError* = object of CatchableError
    ## Base of every error Polars raises (Python Polars' `PolarsError`). IO
    ## failures raise Nim's `IOError` instead.
  ColumnNotFoundError* = object of PolarsError
  ComputeError* = object of PolarsError
  DuplicateError* = object of PolarsError
  InvalidOperationError* = object of PolarsError
  NoDataError* = object of PolarsError
  OutOfBoundsError* = object of PolarsError
  SchemaError* = object of PolarsError
  SchemaFieldNotFoundError* = object of PolarsError
  ShapeError* = object of PolarsError
  StructFieldNotFoundError* = object of PolarsError
  SqlError* = object of PolarsError

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
  ## Raises the last error of the bridge with the type of its Polars variant.
  let m = nq_last_error()
  let msg = if m == nil: "unknown nanuq error" else: $m
  case nq_last_error_kind()
  of nqeGeneric: raise newException(PolarsError, msg)
  of nqeColumnNotFound: raise newException(ColumnNotFoundError, msg)
  of nqeCompute: raise newException(ComputeError, msg)
  of nqeDuplicate: raise newException(DuplicateError, msg)
  of nqeInvalidOperation: raise newException(InvalidOperationError, msg)
  of nqeIo: raise newException(IOError, msg)
  of nqeNoData: raise newException(NoDataError, msg)
  of nqeOutOfBounds: raise newException(OutOfBoundsError, msg)
  of nqeSchema: raise newException(SchemaError, msg)
  of nqeSchemaFieldNotFound: raise newException(SchemaFieldNotFoundError, msg)
  of nqeShape: raise newException(ShapeError, msg)
  of nqeStructFieldNotFound: raise newException(StructFieldNotFoundError, msg)
  of nqeSql: raise newException(SqlError, msg)

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

proc cstrings(xs: openArray[string]): seq[cstring] =
  result = newSeq[cstring](xs.len)
  for i, x in xs: result[i] = x.cstring

template firstOrNil[T](s: seq[T]): ptr T =
  (if s.len == 0: nil else: s[0].unsafeAddr)

proc polarsWrapperVersion*(): string =
  ## Version of the Rust wrapper crate.
  $nq_version()

# ---------------------------------------------------------------------------
# Data types
# ---------------------------------------------------------------------------

type
  DataTypeKind* {.pure.} = enum
    ## Same order as `NqDtype` in the C ABI. `Other` is a dtype Nanuq does not
    ## model yet.
    Boolean, Int8, Int16, Int32, Int64, UInt8, UInt16, UInt32,
    UInt64, Float32, Float64, String, Null, Other

  DataType* = object
    ## A Polars data type. Compare with the constants (`Int64`, `String`, ...).
    ## Dtypes Nanuq does not model yet (dates, lists, ...) have kind
    ## `DataTypeKind.Other` and keep Polars' name.
    case kind*: DataTypeKind
    of DataTypeKind.Other: name*: string
    else: discard

  Schema* = OrderedTable[string, DataType]
    ## Column names and data types, in column order.

const
  Boolean* = DataType(kind: DataTypeKind.Boolean)
  Int8* = DataType(kind: DataTypeKind.Int8)
  Int16* = DataType(kind: DataTypeKind.Int16)
  Int32* = DataType(kind: DataTypeKind.Int32)
  Int64* = DataType(kind: DataTypeKind.Int64)
  UInt8* = DataType(kind: DataTypeKind.UInt8)
  UInt16* = DataType(kind: DataTypeKind.UInt16)
  UInt32* = DataType(kind: DataTypeKind.UInt32)
  UInt64* = DataType(kind: DataTypeKind.UInt64)
  Float32* = DataType(kind: DataTypeKind.Float32)
  Float64* = DataType(kind: DataTypeKind.Float64)
  String* = DataType(kind: DataTypeKind.String)
  Null* = DataType(kind: DataTypeKind.Null)

proc `==`*(a, b: DataType): bool =
  a.kind == b.kind and (a.kind != DataTypeKind.Other or a.name == b.name)

proc `$`*(t: DataType): string =
  ## Polars' short name, e.g. "i64", "str".
  case t.kind
  of DataTypeKind.Boolean: "bool"
  of DataTypeKind.Int8: "i8"
  of DataTypeKind.Int16: "i16"
  of DataTypeKind.Int32: "i32"
  of DataTypeKind.Int64: "i64"
  of DataTypeKind.UInt8: "u8"
  of DataTypeKind.UInt16: "u16"
  of DataTypeKind.UInt32: "u32"
  of DataTypeKind.UInt64: "u64"
  of DataTypeKind.Float32: "f32"
  of DataTypeKind.Float64: "f64"
  of DataTypeKind.String: "str"
  of DataTypeKind.Null: "null"
  of DataTypeKind.Other: t.name

proc isSignedInteger*(t: DataType): bool = t.kind in {DataTypeKind.Int8 .. DataTypeKind.Int64}
proc isUnsignedInteger*(t: DataType): bool = t.kind in {DataTypeKind.UInt8 .. DataTypeKind.UInt64}
proc isInteger*(t: DataType): bool = t.isSignedInteger or t.isUnsignedInteger
proc isFloat*(t: DataType): bool = t.kind in {DataTypeKind.Float32, DataTypeKind.Float64}
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
  if t.kind == DataTypeKind.Other:
    raise newException(InvalidOperationError, "cannot cast to " & t.name & ": Nanuq does not model this dtype yet")
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

proc newDataFrameOf(columns: varargs[Series]): DataFrame =
  var buf = newSeq[ptr NqSeries](columns.len)
  for i, c in columns: buf[i] = c.raw
  wrap nq_df_new(buf.firstOrNil, buf.len.csize_t)

proc blockColumn(line: NimNode): NimNode =
  ## `name: [values]` (or `"name": [...]`) to `series("name", values)`; a `nil`
  ## value makes the bracket a bracket of `Option`s typed from the other values.
  if line.kind != nnkCall or line.len != 2:
    error("newDataFrame expects lines of the form `name: [values]`", line)
  let key = line[0]
  let name =
    case key.kind
    of nnkIdent, nnkSym: newLit(key.strVal)
    of nnkStrLit, nnkRStrLit, nnkTripleStrLit: key
    else:
      error("a column name is an identifier or a string literal", key)
  var vals = line[1]
  if vals.kind == nnkStmtList and vals.len == 1: vals = vals[0]
  var sample: NimNode = nil
  var hasNil = false
  if vals.kind == nnkBracket:
    for v in vals:
      if v.kind == nnkNilLit: hasNil = true
      elif sample.isNil: sample = v
  if hasNil:
    if sample.isNil:
      error("column " & name.strVal & " holds only nil: there is no type to infer", vals)
    let opts = newNimNode(nnkBracket, vals)
    for v in vals:
      opts.add(if v.kind == nnkNilLit:
                 newCall(nnkBracketExpr.newTree(bindSym"none", newCall(ident"typeof", sample)))
               else: newCall(bindSym"some", v))
    vals = opts
  newCall(bindSym"series", name, vals)

macro newDataFrame*(columns: varargs[untyped]): untyped =
  ## Builds a DataFrame from columns of equal length, given as series or as a
  ## block with one `name: [values]` line per column. In the block, a name that
  ## is not a Nim identifier is a string, and `nil` is a missing value:
  ##
  ## .. code-block:: nim
  ##   let a = newDataFrame(series("a", [1, 2, 3]), series("b", ["x", "y", "z"]))
  ##   let b = newDataFrame:
  ##     rider: ["Pogačar", "Seixas"]
  ##     wins: [22, nil]
  ##     "win %": [0.31, 0.12]
  if columns.len == 1 and columns[0].kind == nnkStmtList:
    result = newCall(bindSym"newDataFrameOf")
    for line in columns[0]: result.add blockColumn(line)
  else:
    result = newCall(bindSym"newDataFrameOf")
    for c in columns: result.add c

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
  if k == ord(DataTypeKind.Other):
    DataType(kind: DataTypeKind.Other, name: takeString nq_df_column_dtype(df.raw, column.cstring))
  else:
    DataType(kind: DataTypeKind(k))

proc dtypes*(df: DataFrame): seq[DataType] =
  ## Data types of all columns, in order.
  for name in df.columns: result.add df.dtype(name)

proc schema*(df: DataFrame): Schema =
  ## Column names and data types, in column order.
  for name in df.columns: result[name] = df.dtype(name)

proc getInt*(df: DataFrame, column: string, row: int): int =
  ## Raises `PolarsError` if the cell is null; see `df[column, row, Option[int]]`.
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

proc toList*[T: int | float | bool | string](df: DataFrame, column: string, _: typedesc[T]): seq[T] =
  ## Copies a whole column into a Nim seq. Raises `InvalidOperationError` if the column has
  ## nulls: read it as `Option[T]`, or `fillNull` first.
  ##
  ## `float` reads integer columns too, `string` reads any column; `int` and
  ## `bool` only read their own types.
  let (vals, valid) = readColumn(df, column, T)
  var nulls = 0
  for ok in valid:
    if not ok: inc nulls
  if nulls > 0:
    raise newException(InvalidOperationError, "column '" & column & "' has " & $nulls &
      " null(s); read it as Option[" & $T & "] or fill them first")
  vals

proc toList*[T: int | float | bool | string](df: DataFrame, column: string,
                                             _: typedesc[Option[T]]): seq[Option[T]] =
  ## Copies a whole column into a Nim seq, with `none` for nulls.
  let (vals, valid) = readColumn(df, column, T)
  result = newSeq[Option[T]](vals.len)
  for i, v in vals:
    if valid[i]: result[i] = some(v)

# ---------------------------------------------------------------------------
# Expressions
# ---------------------------------------------------------------------------

type
  ColNs* = object
    ## The type of `col`: call it with names or types, or write `col.name`.

const col* = ColNs()
  ## Columns by name or type: `col("a")`, `col.a` (the same), `col("a", "b")`,
  ## `col(SomeNumber)`. `col.name` works for any name that is a Nim identifier
  ## and not taken by Nim first (`type`, `repr`, `sizeof`): use `col("type")`.

proc `()`*(c: ColNs, name: string): Expr =
  ## The column `name`.
  wrap nq_expr_col(name.cstring)

template `.`*(c: ColNs, name: untyped): Expr =
  ## `col.race` is `col("race")`.
  c(astToStr(name))

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
defBinOp(`/`, nqDiv)    # true division, as in Python Polars and Nim
defBinOp(`==`, nqEq)
defBinOp(`!=`, nqNotEq)
defBinOp(`<`, nqLt)
defBinOp(`<=`, nqLtEq)
defBinOp(`>`, nqGt)
defBinOp(`>=`, nqGtEq)
defBinOp(`and`, nqAnd)
defBinOp(`or`, nqOr)
defBinOp(`mod`, nqMod)
defBinOp(`div`, nqFloorDiv)
defBinOp(`^`, nqPow)
defBinOp(pow, nqPow)

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
proc std*(e: Expr, ddof = 1): Expr =
  ## Standard deviation; `ddof = 1` gives the sample standard deviation.
  wrap nq_expr_var_std(e.raw, ddof.uint8, false)
proc `var`*(e: Expr, ddof = 1): Expr =
  ## Variance; `ddof = 1` gives the sample variance. `var` is a Nim keyword:
  ## write `e.var`, or `` `var`(e) ``.
  wrap nq_expr_var_std(e.raw, ddof.uint8, true)
proc median*(e: Expr): Expr = unary(e, nqMedian)
proc len*(e: Expr): Expr = unary(e, nqLen)
  ## Number of rows, nulls included (`count` leaves nulls out).
proc abs*(e: Expr): Expr = unary(e, nqAbs)
proc `-`*(e: Expr): Expr = unary(e, nqNeg)

proc nullCount*(e: Expr): Expr = unary(e, nqNullCount)
  ## Number of nulls, as an aggregation (u32).
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
# More expressions: conditionals, membership, rounding, fill strategies, windows
# ---------------------------------------------------------------------------

type
  ClosedInterval* {.pure.} = enum
    ## Which ends of an `isBetween` range are included (Polars' `ClosedInterval`).
    Both, Left, Right, None
  QuantileMethod* {.pure.} = enum
    ## How `quantile` picks or interpolates a value (Polars' `QuantileMethod`).
    Nearest, Lower, Higher, Midpoint, Linear, Equiprobable
  FillNullStrategy* {.pure.} = enum
    ## How `fillNull` fills nulls (Polars' `FillNullStrategy`).
    Forward, Backward, Mean, Min, Max, Zero, One
  RoundMode* {.pure.} = enum
    ## How `round` breaks ties (Polars' `RoundMode`).
    HalfToEven, HalfAwayFromZero, ToZero
  RankMethod* {.pure.} = enum
    ## How `rank` treats ties (Polars' `RankMethod`).
    Average, Min, Max, Dense, Ordinal, Random

  When* = object
    ## A conditional chain waiting for `then`.
    conds, values: seq[Expr]
  Then* = object
    ## A conditional chain that can take another `when`, an `otherwise`, or be
    ## used as an `Expr` (rows matching no condition are null).
    conds, values: seq[Expr]

proc whenThen(t: Then, otherwise: Expr): Expr =
  let c = raws(t.conds)
  let v = raws(t.values)
  let o = if otherwise.isNil: nil else: otherwise.raw
  wrap nq_expr_when_then(c.firstOrNil, v.firstOrNil, c.len.csize_t, o)

proc `when`*(cond: Expr): When =
  ## Starts a conditional chain, as Polars' `when`:
  ## `` `when`(col("w") < 150).then("cub").otherwise("big") ``. `when` is a Nim
  ## keyword, so the first call needs backticks (the `choose` macro avoids them).
  When(conds: @[cond])
proc `when`*(t: Then, cond: Expr): When = When(conds: t.conds & cond, values: t.values)
proc then*[T](w: When, value: T): Then =
  ## The value for rows matching the last condition. Strings are literals: use
  ## `col("x")` for a column.
  Then(conds: w.conds, values: w.values & lit(value))
proc otherwise*[T](t: Then, value: T): Expr =
  ## The value for rows matching no condition.
  whenThen(t, lit(value))
converter toExpr*(t: Then): Expr =
  ## A chain without `otherwise`: rows matching no condition are null.
  whenThen(t, nil)
proc `$`*(t: Then): string = $toExpr(t)

macro choose*(body: untyped): untyped =
  ## A conditional expression written as Nim's `if`/`elif`/`else`; it builds
  ## the same `when/then/otherwise` chain:
  ##
  ## .. code-block:: nim
  ##   let size = choose:
  ##     if col("w") < 150: "cub"
  ##     elif col("w") < 500: "adult"
  ##     else: "chonk"
  ##
  ## Without `else`, rows matching no condition are null.
  var n = body
  if n.kind == nnkStmtList and n.len == 1: n = n[0]
  if n.kind notin {nnkIfStmt, nnkIfExpr}:
    error("choose expects an if/elif/else expression", body)
  proc value(x: NimNode): NimNode =
    if x.kind == nnkStmtList and x.len == 1: x[0] else: x
  var chain: NimNode = nil
  for branch in n:
    case branch.kind
    of nnkElifBranch, nnkElifExpr:
      let w = if chain.isNil: newCall(ident"when", branch[0])
              else: newCall(ident"when", chain, branch[0])
      chain = newCall(ident"then", w, value(branch[1]))
    of nnkElse, nnkElseExpr:
      return newCall(ident"otherwise", chain, value(branch[0]))
    else:
      error("choose expects an if/elif/else expression", branch)
  result = newCall(ident"toExpr", chain)

proc isIn*(e: Expr, other: Expr, nullsEqual = false): Expr =
  ## True where the value is among the values of `other`.
  wrap nq_expr_is_in(e.raw, other.raw, nullsEqual)
proc isIn*[T: int | float | bool | string](e: Expr, values: openArray[T],
                                           nullsEqual = false): Expr =
  ## True where the value is one of `values`: `col("a").isIn([1, 3])`.
  let s = series("", values)
  e.isIn(wrap nq_expr_lit_series(s.raw), nullsEqual)

proc isBetween*[A, B](e: Expr, lower: A, upper: B, closed = ClosedInterval.Both): Expr =
  ## True where `lower <= value <= upper` (ends included as `closed` says).
  let lo = lit(lower)
  let hi = lit(upper)
  wrap nq_expr_is_between(e.raw, lo.raw, hi.raw, NqClosedInterval(ord(closed)))

proc quantile*(e: Expr, q: float, interpolation = QuantileMethod.Nearest): Expr =
  ## The `q` quantile (0 to 1). `interpolation` is Python Polars' name for the method.
  wrap nq_expr_quantile(e.raw, q, NqQuantileMethod(ord(interpolation)))

proc round*(e: Expr, decimals = 0, mode = RoundMode.HalfToEven): Expr =
  ## Rounds to `decimals` places; ties go to the even digit by default, as in Polars.
  if decimals < 0: raise newException(ValueError, "round decimals must not be negative")
  wrap nq_expr_round(e.raw, decimals.uint32, NqRoundMode(ord(mode)))

proc fillNull*(e: Expr, strategy: FillNullStrategy, limit = none(int)): Expr =
  ## Fills nulls with a strategy: `fillNull(Forward)`, `fillNull(Mean)`. `limit`
  ## bounds how many consecutive nulls `Forward` and `Backward` fill.
  if limit.isSome and limit.get < 0:
    raise newException(ValueError, "fillNull limit must not be negative")
  wrap nq_expr_fill_null_strategy(e.raw, NqFillNullStrategy(ord(strategy)), limit.isSome,
                                  limit.get(0).uint32)
proc fillNull*(e: Expr, strategy: FillNullStrategy, limit: int): Expr =
  e.fillNull(strategy, some(limit))
proc forwardFill*(e: Expr, limit = none(int)): Expr =
  ## Fills each null with the last non-null value above it.
  e.fillNull(FillNullStrategy.Forward, limit)
proc forwardFill*(e: Expr, limit: int): Expr = e.forwardFill(some(limit))
proc backwardFill*(e: Expr, limit = none(int)): Expr =
  ## Fills each null with the next non-null value below it.
  e.fillNull(FillNullStrategy.Backward, limit)
proc backwardFill*(e: Expr, limit: int): Expr = e.backwardFill(some(limit))

proc rank*(e: Expr, rankMethod = RankMethod.Average, descending = false,
           seed = none(int)): Expr =
  ## Rank of each value, from 1: `rank(Min, descending = true)` gives tied
  ## values the same place. `Average` gives f64, the other methods u32. `seed`
  ## makes `Random` repeatable. Python's `method` is a Nim keyword, so the
  ## method is passed by position.
  if seed.isSome and seed.get < 0: raise newException(ValueError, "rank seed must not be negative")
  wrap nq_expr_rank(e.raw, NqRankMethod(ord(rankMethod)), descending, seed.isSome,
                    seed.get(0).uint64)
proc rank*(e: Expr, rankMethod: RankMethod, descending = false, seed: int): Expr =
  e.rank(rankMethod, descending, some(seed))

proc over*(e: Expr, partitionBy: openArray[Expr]): Expr =
  ## Computes `e` per group of `partitionBy` and gives each row its group's value.
  let b = raws(partitionBy)
  wrap nq_expr_over(e.raw, b.firstOrNil, b.len.csize_t)
proc over*(e: Expr, partitionBy: openArray[string]): Expr =
  var keys: seq[Expr]
  for n in partitionBy: keys.add col(n)
  e.over(keys)
proc over*(e: Expr, partitionBy: string): Expr = e.over([col(partitionBy)])

# ---------------------------------------------------------------------------
# Column selectors
# ---------------------------------------------------------------------------

type
  DtypeClass {.pure.} = enum
    ## Same order as `NqDtypeClass` in lib.rs.
    Numeric, Integer, SignedInteger, UnsignedInteger, Float
  Selector* = object
    ## Several columns at once: by Nim type (`col(SomeNumber)`, `col(float, int)`),
    ## by name (`col("a", "b")`, `all()`), minus `exclude`d names. Converts to
    ## `Expr`, which Polars expands to one column per selected column.
    names: seq[string]
    dtypes: seq[DataType]
    classes: set[DtypeClass]
    wildcard: bool
    excluded: seq[string]
  ExprName* = object
    ## `e.name`, for `suffix` and `prefix`.
    e: Expr

converter toExpr*(s: Selector): Expr =
  let n = cstrings(s.names)
  var d = newSeq[NqDtype](s.dtypes.len)
  for i, t in s.dtypes: d[i] = t.code
  var bits = 0'u32
  for c in s.classes: bits = bits or (1'u32 shl ord(c))
  let x = cstrings(s.excluded)
  wrap nq_expr_selector(n.firstOrNil, n.len.csize_t, d.firstOrNil, d.len.csize_t, bits,
                        s.wildcard, x.firstOrNil, x.len.csize_t)
proc `$`*(s: Selector): string = $toExpr(s)

proc classSelector(c: DtypeClass): Selector = Selector(classes: {c})
proc dtypeSelector(t: DataType): Selector = Selector(dtypes: @[t])
proc union(a, b: Selector): Selector =
  Selector(names: a.names & b.names, dtypes: a.dtypes & b.dtypes, classes: a.classes + b.classes,
           wildcard: a.wildcard or b.wildcard, excluded: a.excluded & b.excluded)

macro `()`*(c: ColNs, T: typedesc, more: varargs[typed]): untyped =
  ## Columns by Nim type: a typeclass selects a Polars dtype category
  ## (`col(SomeNumber)`, `SomeInteger`, `SomeSignedInt`, `SomeUnsignedInt`,
  ## `SomeFloat`), a concrete type selects its dtype (`col(int)` is i64), and
  ## several types select their union (`col(float, int)`).
  proc one(t: NimNode): NimNode =
    let classes = {"SomeNumber": "Numeric", "SomeInteger": "Integer",
                   "SomeSignedInt": "SignedInteger", "SomeUnsignedInt": "UnsignedInteger",
                   "SomeFloat": "Float"}
    if t.kind == nnkSym:
      for (tc, cls) in classes:
        if t.strVal == tc:
          return newCall(bindSym"classSelector",
                         newDotExpr(bindSym"DtypeClass", ident(cls)))
    newCall(bindSym"dtypeSelector", newCall(bindSym"dataType", t))
  result = one(T)
  for m in more: result = newCall(bindSym"union", result, one(m))

proc nameList(a, b: string, more: openArray[string]): seq[string] =
  result = @[a, b]
  for m in more: result.add m

proc `()`*(c: ColNs, a, b: string, more: varargs[string]): Selector =
  ## Several columns by name, in this order: `col("a", "b")`.
  Selector(names: nameList(a, b, more))

proc all*(): Selector =
  ## Every column: `all().exclude("id")`.
  Selector(wildcard: true)

proc exclude*(s: Selector, names: varargs[string]): Selector =
  ## The selection without the named columns.
  result = s
  for n in names: result.excluded.add n

proc name*(e: Expr): ExprName = ExprName(e: e)
proc suffix*(n: ExprName, s: string): Expr =
  ## Appends `s` to the name of every column the expression produces:
  ## `col(SomeNumber).mean.name.suffix("_mean")`.
  wrap nq_expr_name_affix(n.e.raw, s.cstring, false)
proc prefix*(n: ExprName, s: string): Expr =
  ## Prepends `s` to the name of every column the expression produces.
  wrap nq_expr_name_affix(n.e.raw, s.cstring, true)

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

proc sort*(lf: LazyFrame, by: openArray[Expr], descending: openArray[bool] = [],
           nullsLast: openArray[bool] = [], maintainOrder = false): LazyFrame =
  ## Sorts by several keys. `descending` and `nullsLast` hold one value per key,
  ## or one value for every key; empty means false.
  let b = raws(by)
  let d = @descending
  let nl = @nullsLast
  wrap nq_lf_sort_by(lf.raw, b.firstOrNil, b.len.csize_t, d.firstOrNil, d.len.csize_t,
                     nl.firstOrNil, nl.len.csize_t, maintainOrder)

proc sort*(lf: LazyFrame, by: openArray[string], descending: openArray[bool] = [],
           nullsLast: openArray[bool] = [], maintainOrder = false): LazyFrame =
  ## Sorts by several columns: `sort(["species", "mass"], descending = [false, true])`.
  var keys: seq[Expr]
  for n in by: keys.add col(n)
  lf.sort(keys, descending, nullsLast, maintainOrder)

proc sort*(lf: LazyFrame, by: string, descending = false, nullsLast = false,
           maintainOrder = false): LazyFrame =
  lf.sort([col(by)], [descending], [nullsLast], maintainOrder)

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

# ---------------------------------------------------------------------------
# Joins and concatenation
# ---------------------------------------------------------------------------

type
  JoinType* {.pure.} = enum
    ## How rows are matched (Polars' `JoinType`). Same order as `NqJoinType`.
    Inner, Left, Right, Full, Semi, Anti, Cross
  JoinValidation* {.pure.} = enum
    ## Which side's keys must be unique (Polars' `JoinValidation`).
    ManyToMany, ManyToOne, OneToMany, OneToOne
  MaintainOrderJoin* {.pure.} = enum
    ## Row order of the result (Polars' `MaintainOrderJoin`). With `None`,
    ## the order is not guaranteed.
    None, Left, Right, LeftRight, RightLeft
  ConcatMethod* {.pure.} = enum
    ## How frames are concatenated (Python Polars' `how` in `pl.concat`).
    Vertical, VerticalRelaxed, Horizontal, Diagonal, DiagonalRelaxed

proc joinImpl(lf, other: LazyFrame, leftOn, rightOn: openArray[Expr], how: JoinType,
              suffix: string, validate: JoinValidation, nullsEqual: bool,
              coalesce: Option[bool], maintainOrder: MaintainOrderJoin): LazyFrame =
  let l = raws(leftOn)
  let r = raws(rightOn)
  let c = if coalesce.isNone: -1'i32 elif coalesce.get: 1'i32 else: 0'i32
  wrap nq_lf_join(lf.raw, other.raw, l.firstOrNil, l.len.csize_t, r.firstOrNil, r.len.csize_t,
                  NqJoinType(ord(how)), suffix.cstring, NqJoinValidation(ord(validate)),
                  nullsEqual, c, NqMaintainOrderJoin(ord(maintainOrder)))

proc cols(names: openArray[string]): seq[Expr] =
  for n in names: result.add col(n)

proc join*(lf, other: LazyFrame, on: openArray[Expr], how = JoinType.Inner,
           suffix = "_right", validate = JoinValidation.ManyToMany, nullsEqual = false,
           coalesce = none(bool), maintainOrder = MaintainOrderJoin.None): LazyFrame =
  ## Joins on key expressions that have the same name on both sides.
  ## `coalesce`: `none` for Polars' default per join type. Row order is not
  ## guaranteed unless `maintainOrder` says so.
  joinImpl(lf, other, on, on, how, suffix, validate, nullsEqual, coalesce, maintainOrder)

proc join*(lf, other: LazyFrame, on: openArray[string], how = JoinType.Inner,
           suffix = "_right", validate = JoinValidation.ManyToMany, nullsEqual = false,
           coalesce = none(bool), maintainOrder = MaintainOrderJoin.None): LazyFrame =
  ## Joins on columns with the same name on both sides: `a.join(b, on = ["k"], how = Left)`.
  let k = cols(on)
  joinImpl(lf, other, k, k, how, suffix, validate, nullsEqual, coalesce, maintainOrder)

proc join*(lf, other: LazyFrame, leftOn, rightOn: openArray[Expr], how = JoinType.Inner,
           suffix = "_right", validate = JoinValidation.ManyToMany, nullsEqual = false,
           coalesce = none(bool), maintainOrder = MaintainOrderJoin.None): LazyFrame =
  ## Joins on different key expressions on each side.
  joinImpl(lf, other, leftOn, rightOn, how, suffix, validate, nullsEqual, coalesce, maintainOrder)

proc join*(lf, other: LazyFrame, leftOn, rightOn: openArray[string], how = JoinType.Inner,
           suffix = "_right", validate = JoinValidation.ManyToMany, nullsEqual = false,
           coalesce = none(bool), maintainOrder = MaintainOrderJoin.None): LazyFrame =
  ## Joins on differently named columns: `leftOn = ["id"], rightOn = ["station_id"]`.
  joinImpl(lf, other, cols(leftOn), cols(rightOn), how, suffix, validate, nullsEqual,
           coalesce, maintainOrder)

proc join*(lf, other: LazyFrame, how: JoinType, suffix = "_right",
           maintainOrder = MaintainOrderJoin.None): LazyFrame =
  ## A join without keys: only `how = Cross` (every pair of rows) is valid.
  joinImpl(lf, other, [], [], how, suffix, JoinValidation.ManyToMany, false, none(bool),
           maintainOrder)

proc concat*(frames: openArray[LazyFrame], how = ConcatMethod.Vertical): LazyFrame =
  ## Concatenates frames: `Vertical` (same columns), `VerticalRelaxed` (common
  ## supertypes), `Horizontal` (side by side), `Diagonal` (union of columns,
  ## missing ones null) or `DiagonalRelaxed`.
  var r = newSeq[ptr NqLazyFrame](frames.len)
  for i, f in frames: r[i] = f.raw
  wrap nq_lf_concat(r.firstOrNil, r.len.csize_t, NqConcat(ord(how)))

proc limit*(lf: LazyFrame, n: int): LazyFrame = wrap nq_lf_limit(lf.raw, n.uint32)

# ---------------------------------------------------------------------------
# Frame verbs
# ---------------------------------------------------------------------------

type
  UniqueKeepStrategy* {.pure.} = enum
    ## Which row of a group of duplicates `unique` keeps (Polars'
    ## `UniqueKeepStrategy`). `Any` lets Polars pick, which is fastest.
    First, Last, None, Any

proc drop*(lf: LazyFrame, columns: openArray[string], strict = true): LazyFrame =
  ## Removes columns: `drop(["a", "b"])`. With `strict`, a missing column raises
  ## `PolarsError`.
  let c = cstrings(columns)
  wrap nq_lf_drop(lf.raw, c.firstOrNil, c.len.csize_t, strict)

proc drop*(lf: LazyFrame, column: string, strict = true): LazyFrame =
  ## Removes one column: `drop("a")`.
  lf.drop([column], strict)

proc rename*(lf: LazyFrame, mapping: openArray[(string, string)], strict = true): LazyFrame =
  ## Renames columns: `rename({"old": "new"})`. With `strict`, a missing column
  ## raises `PolarsError`.
  var olds, news: seq[cstring]
  for (o, n) in mapping:
    olds.add o.cstring
    news.add n.cstring
  wrap nq_lf_rename(lf.raw, olds.firstOrNil, news.firstOrNil, olds.len.csize_t, strict)

proc slice*(lf: LazyFrame, offset: int, length: int): LazyFrame =
  ## `length` rows from `offset`; a negative offset counts from the end.
  if length < 0: raise newException(ValueError, "slice length must not be negative")
  wrap nq_lf_slice(lf.raw, offset.int64, min(length, high(uint32).int).uint32)

proc slice*(lf: LazyFrame, offset: int): LazyFrame =
  ## The rows from `offset` to the end.
  wrap nq_lf_slice(lf.raw, offset.int64, high(uint32))

proc head*(lf: LazyFrame, n = 5): LazyFrame = lf.limit(n)
proc tail*(lf: LazyFrame, n = 5): LazyFrame = lf.slice(-n, n)
proc reverse*(lf: LazyFrame): LazyFrame = wrap nq_lf_reverse(lf.raw)

proc withRowIndex*(lf: LazyFrame, name = "index", offset = 0): LazyFrame =
  ## Adds a row number column, first, counting from `offset`.
  if offset < 0: raise newException(ValueError, "row index offset must not be negative")
  wrap nq_lf_with_row_index(lf.raw, name.cstring, offset.uint32)

proc unique*(lf: LazyFrame, subset: openArray[string] = [], keep = UniqueKeepStrategy.Any,
             maintainOrder = false): LazyFrame =
  ## Drops duplicate rows, judged on the `subset` columns (all when empty).
  let c = cstrings(subset)
  wrap nq_lf_unique(lf.raw, c.firstOrNil, c.len.csize_t, NqUniqueKeepStrategy(ord(keep)),
                    maintainOrder)

proc unique*(lf: LazyFrame, subset: string, keep = UniqueKeepStrategy.Any,
             maintainOrder = false): LazyFrame =
  ## Drops rows whose `subset` column value was already seen: `unique("k", keep = First)`.
  lf.unique([subset], keep, maintainOrder)

proc explain*(lf: LazyFrame): string =
  ## The optimized query plan.
  takeString nq_lf_explain(lf.raw)

# ---------------------------------------------------------------------------
# CSV
# ---------------------------------------------------------------------------

type
  QuoteStyle* {.pure.} = enum
    ## When `writeCsv` quotes a field (Polars' `QuoteStyle`). `Necessary`
    ## quotes only fields that hold a quote, the separator or a line break.
    Necessary, Always, NonNumeric, Never

proc toOpt(x: int): Option[int] = some(x)
proc toOpt(x: Option[int]): Option[int] = x
proc toC(x: Option[int]): int64 = (if x.isSome: x.get.int64 else: -1'i64)

proc scanCsv*(path: string, separator = ',', hasHeader = true,
              nullValues: openArray[string] = [],
              schemaOverrides: openArray[(string, DataType)] = [],
              skipRows = 0, nRows: int | Option[int] = none(int),
              columns: openArray[string] = [],
              inferSchemaLength: int | Option[int] = some(100),
              ignoreErrors = false, decimalComma = false): LazyFrame =
  ## Lazily reads a CSV file; nothing is read until the query runs. `path` may be
  ## a glob such as `"logs/*.csv"` when every file has the same columns.
  ##
  ## Fields equal to one of `nullValues` (e.g. `["NA"]`) are null; empty fields
  ## always are. `schemaOverrides` sets the dtype of some columns
  ## (`{"bears": Int64}`), the rest are inferred from the first
  ## `inferSchemaLength` rows (`none(int)`: all rows). `skipRows` skips lines
  ## before the header, `nRows` limits the rows read and `columns` keeps only
  ## those columns, in that order.
  let nulls = cstrings(nullValues)
  var names = newSeq[cstring](schemaOverrides.len)
  var codes = newSeq[NqDtype](schemaOverrides.len)
  for i, (n, t) in schemaOverrides:
    names[i] = n.cstring
    codes[i] = t.code
  result = wrap nq_lf_scan_csv(path.cstring, separator.uint8, hasHeader,
                               nulls.firstOrNil, nulls.len.csize_t,
                               names.firstOrNil, codes.firstOrNil, names.len.csize_t,
                               skipRows.csize_t, toOpt(nRows).toC,
                               toOpt(inferSchemaLength).toC, ignoreErrors, decimalComma)
  if columns.len > 0:
    var sel = newSeq[Expr](columns.len)
    for i, c in columns: sel[i] = col(c)
    result = result.select(sel)

proc readCsv*(path: string, separator = ',', hasHeader = true,
              nullValues: openArray[string] = [],
              schemaOverrides: openArray[(string, DataType)] = [],
              skipRows = 0, nRows: int | Option[int] = none(int),
              columns: openArray[string] = [],
              inferSchemaLength: int | Option[int] = some(100),
              ignoreErrors = false, decimalComma = false): DataFrame =
  ## Reads a CSV file now: `scanCsv(...).collect`, with the same options.
  ##
  ## .. code-block:: nim
  ##   let df = readCsv("data.csv", separator = ';', nullValues = ["NA"],
  ##                    schemaOverrides = {"bears": Int64})
  scanCsv(path, separator, hasHeader, nullValues, schemaOverrides, skipRows, nRows,
          columns, inferSchemaLength, ignoreErrors, decimalComma).collect

proc writeCsv*(df: DataFrame, path: string, separator = ',', includeHeader = true,
               nullValue = "", quoteStyle = QuoteStyle.Necessary,
               floatPrecision: int | Option[int] = none(int), decimalComma = false) =
  ## Writes `df` as CSV. Nulls are written as `nullValue`; `floatPrecision`
  ## sets the number of decimals for floats (`none(int)`: as many as needed).
  let p = toOpt(floatPrecision)
  if not nq_df_write_csv(df.raw, path.cstring, separator.uint8, includeHeader,
                         nullValue.cstring, NqQuoteStyle(ord(quoteStyle)),
                         (if p.isSome: p.get.int32 else: -1'i32), decimalComma):
    raiseLast()

# Eager shortcuts: run a single lazy step and collect.
proc select*(df: DataFrame, exprs: varargs[Expr]): DataFrame = df.lazy.select(exprs).collect
proc withColumns*(df: DataFrame, exprs: varargs[Expr]): DataFrame = df.lazy.withColumns(exprs).collect
proc filter*(df: DataFrame, predicate: Expr): DataFrame = df.lazy.filter(predicate).collect
proc sort*(df: DataFrame, by: string, descending = false, nullsLast = false,
           maintainOrder = false): DataFrame =
  df.lazy.sort(by, descending, nullsLast, maintainOrder).collect
proc sort*(df: DataFrame, by: openArray[string], descending: openArray[bool] = [],
           nullsLast: openArray[bool] = [], maintainOrder = false): DataFrame =
  df.lazy.sort(by, descending, nullsLast, maintainOrder).collect
proc sort*(df: DataFrame, by: openArray[Expr], descending: openArray[bool] = [],
           nullsLast: openArray[bool] = [], maintainOrder = false): DataFrame =
  df.lazy.sort(by, descending, nullsLast, maintainOrder).collect
proc groupBy*(df: DataFrame, by: varargs[Expr]): LazyGroupBy = df.lazy.groupBy(by)
proc dropNulls*(df: DataFrame, subset: varargs[string]): DataFrame = df.lazy.dropNulls(subset).collect
proc `cast`*(df: DataFrame, dtypes: openArray[(string, DataType)], strict = true): DataFrame =
  df.lazy.cast(dtypes, strict).collect
proc `cast`*(df: DataFrame, dtype: DataType, strict = true): DataFrame = df.lazy.cast(dtype, strict).collect
proc `cast`*(df: DataFrame, T: typedesc, strict = true): DataFrame = df.lazy.cast(T, strict).collect

proc join*(df, other: DataFrame, on: openArray[string], how = JoinType.Inner,
           suffix = "_right", validate = JoinValidation.ManyToMany, nullsEqual = false,
           coalesce = none(bool), maintainOrder = MaintainOrderJoin.None): DataFrame =
  df.lazy.join(other.lazy, on, how, suffix, validate, nullsEqual, coalesce, maintainOrder).collect
proc join*(df, other: DataFrame, on: openArray[Expr], how = JoinType.Inner,
           suffix = "_right", validate = JoinValidation.ManyToMany, nullsEqual = false,
           coalesce = none(bool), maintainOrder = MaintainOrderJoin.None): DataFrame =
  df.lazy.join(other.lazy, on, how, suffix, validate, nullsEqual, coalesce, maintainOrder).collect
proc join*(df, other: DataFrame, leftOn, rightOn: openArray[string], how = JoinType.Inner,
           suffix = "_right", validate = JoinValidation.ManyToMany, nullsEqual = false,
           coalesce = none(bool), maintainOrder = MaintainOrderJoin.None): DataFrame =
  df.lazy.join(other.lazy, leftOn, rightOn, how, suffix, validate, nullsEqual, coalesce,
               maintainOrder).collect
proc join*(df, other: DataFrame, leftOn, rightOn: openArray[Expr], how = JoinType.Inner,
           suffix = "_right", validate = JoinValidation.ManyToMany, nullsEqual = false,
           coalesce = none(bool), maintainOrder = MaintainOrderJoin.None): DataFrame =
  df.lazy.join(other.lazy, leftOn, rightOn, how, suffix, validate, nullsEqual, coalesce,
               maintainOrder).collect
proc join*(df, other: DataFrame, how: JoinType, suffix = "_right",
           maintainOrder = MaintainOrderJoin.None): DataFrame =
  df.lazy.join(other.lazy, how, suffix, maintainOrder).collect
proc concat*(frames: openArray[DataFrame], how = ConcatMethod.Vertical): DataFrame =
  var lfs: seq[LazyFrame]
  for f in frames: lfs.add f.lazy
  concat(lfs, how).collect

proc drop*(df: DataFrame, columns: openArray[string], strict = true): DataFrame =
  df.lazy.drop(columns, strict).collect
proc drop*(df: DataFrame, column: string, strict = true): DataFrame =
  df.lazy.drop(column, strict).collect
proc rename*(df: DataFrame, mapping: openArray[(string, string)], strict = true): DataFrame =
  df.lazy.rename(mapping, strict).collect
proc slice*(df: DataFrame, offset: int, length: int): DataFrame = df.lazy.slice(offset, length).collect
proc slice*(df: DataFrame, offset: int): DataFrame = df.lazy.slice(offset).collect
proc tail*(df: DataFrame, n = 5): DataFrame = df.lazy.tail(n).collect
proc reverse*(df: DataFrame): DataFrame = df.lazy.reverse.collect
proc withRowIndex*(df: DataFrame, name = "index", offset = 0): DataFrame =
  df.lazy.withRowIndex(name, offset).collect
proc unique*(df: DataFrame, subset: openArray[string] = [], keep = UniqueKeepStrategy.Any,
             maintainOrder = false): DataFrame =
  df.lazy.unique(subset, keep, maintainOrder).collect
proc unique*(df: DataFrame, subset: string, keep = UniqueKeepStrategy.Any,
             maintainOrder = false): DataFrame =
  df.lazy.unique(subset, keep, maintainOrder).collect

proc sampleImpl(df: DataFrame, n: int, fraction: float, byFraction, withReplacement,
                shuffle: bool, seed: Option[int]): DataFrame =
  if seed.isSome and seed.get < 0:
    raise newException(ValueError, "sample seed must not be negative")
  wrap nq_df_sample(df.raw, n.csize_t, fraction, byFraction, withReplacement, shuffle,
                    seed.isSome, seed.get(0).uint64)

proc setRandomSeed*(seed: int) =
  ## Seeds Polars' global random generator: random operations without a `seed`
  ## of their own (such as `sample`) repeat from here on, like `randomize(seed)`.
  if seed < 0: raise newException(ValueError, "random seed must not be negative")
  nq_set_random_seed(seed.uint64)

proc sample*(df: DataFrame, n: int, withReplacement = false, shuffle = false,
             seed = none(int)): DataFrame =
  ## `n` random rows. Random unless `seed` is given (or `setRandomSeed` was called).
  if n < 0: raise newException(ValueError, "sample size must not be negative")
  sampleImpl(df, n, 0.0, false, withReplacement, shuffle, seed)

proc sample*(df: DataFrame, n: int, withReplacement = false, shuffle = false,
             seed: int): DataFrame =
  ## `n` random rows; the same `seed` gives the same rows: `df.sample(3, seed = 42)`.
  df.sample(n, withReplacement, shuffle, some(seed))

proc sample*(df: DataFrame, fraction: float, withReplacement = false, shuffle = false,
             seed = none(int)): DataFrame =
  ## A random `fraction` of the rows: `df.sample(fraction = 0.1)`.
  sampleImpl(df, 0, fraction, true, withReplacement, shuffle, seed)

proc sample*(df: DataFrame, fraction: float, withReplacement = false, shuffle = false,
             seed: int): DataFrame =
  df.sample(fraction, withReplacement, shuffle, some(seed))

# ---------------------------------------------------------------------------
# Inspection: glimpse and describe, ported from Python Polars
# ---------------------------------------------------------------------------

proc pyRepr(s: string): string =
  ## A string quoted as Python's `repr` quotes it.
  let q = if '\'' in s and '"' notin s: '"' else: '\''
  result.add q
  for c in s:
    case c
    of '\\': result.add "\\\\"
    of '\n': result.add "\\n"
    of '\r': result.add "\\r"
    of '\t': result.add "\\t"
    else:
      if c == q: result.add '\\'
      result.add c
  result.add q

proc glimpse*(df: DataFrame, maxItemsPerColumn = 10, maxColnameLength = 50): string =
  ## A dense preview, one line per column, as Python Polars' `glimpse`:
  ## `echo df.glimpse`. Shows the first `maxItemsPerColumn` values of each column.
  let head = df.head(min(maxItemsPerColumn, df.height))
  var rows: seq[(string, string, string)]
  for name in df.columns:
    let dt = df.dtype(name)
    var shown = name
    if shown.runeLen > maxColnameLength:
      shown = shown.runeSubStr(0, maxColnameLength - 1) & "…"
    var vals: seq[string]
    for v in head.toList(name, Option[string]):
      if v.isNone: vals.add "null"
      elif dt == String: vals.add pyRepr(v.get)
      elif dt == Boolean: vals.add(if v.get == "true": "True" else: "False")
      else: vals.add v.get
    rows.add (shown, "<" & $dt & ">", vals.join(", "))
  var wName, wType = 0
  for (n, t, _) in rows:
    wName = max(wName, n.runeLen)
    wType = max(wType, t.runeLen)
  result = "Rows: " & $df.height & "\nColumns: " & $df.width & "\n"
  for (n, t, v) in rows:
    result.add "$ " & n & repeat(' ', wName - n.runeLen) & " " &
      repeat(' ', wType - t.runeLen) & t & " " & v & "\n"

proc percentLabel(q: float): string =
  ## Python's `f"{q * 100:g}%"`.
  let v = q * 100
  result = formatFloat(v, ffDecimal, 6)
  result = result.strip(leading = false, chars = {'0'}).strip(leading = false, chars = {'.'})
  result.add '%'

proc describe*(lf: LazyFrame, percentiles: openArray[float] = [0.25, 0.5, 0.75],
               interpolation = QuantileMethod.Nearest): DataFrame =
  ## Summary statistics, as Python Polars' `describe`: a `statistic` column and one
  ## column per input column (f64 for numeric and boolean columns, str otherwise).
  let schema = lf.collectSchema
  if schema.len == 0:
    raise newException(InvalidOperationError, "cannot describe a frame that has no columns")
  var metrics = @["count", "null_count", "mean", "std", "min"]
  for q in percentiles: metrics.add percentLabel(q)
  metrics.add "max"
  var exprs: seq[Expr]
  var numericResult: seq[bool]
  var computed: seq[seq[bool]]  # per column, per metric: was it computed
  for name, dt in schema:
    let numeric = dt.isNumeric
    let asFloat = numeric or dt.kind in {DataTypeKind.Boolean, DataTypeKind.Null}
    let minMax = dt.kind notin {DataTypeKind.Null, DataTypeKind.Other}
    let target = if asFloat: Float64 else: String
    var have: seq[bool]
    proc add(e: Expr, ok: bool, metric: string) =
      have.add ok
      if ok: exprs.add e.cast(target).alias(metric & ":" & name)
    let c = col(name)
    add(c.count, true, "count")
    add(c.nullCount, true, "null_count")
    add(c.mean, numeric or dt == Boolean, "mean")
    add(c.std, numeric, "std")
    add(c.min, minMax, "min")
    for q in percentiles:
      add(c.quantile(q, interpolation), numeric, $q)
    add(c.max, minMax, "max")
    numericResult.add asFloat
    computed.add have
  let row = lf.select(exprs).collect
  var columns = @[series("statistic", metrics)]
  var i = 0
  for name, dt in schema:
    if numericResult[i]:
      var vals: seq[Option[float]]
      for m, metric in metrics:
        let label = (if m in 5 ..< 5 + percentiles.len: $percentiles[m - 5] else: metric)
        vals.add(if computed[i][m]: row[label & ":" & name, 0, Option[float]] else: none(float))
      columns.add series(name, vals)
    else:
      var vals: seq[Option[string]]
      for m, metric in metrics:
        let label = (if m in 5 ..< 5 + percentiles.len: $percentiles[m - 5] else: metric)
        vals.add(if computed[i][m]: row[label & ":" & name, 0, Option[string]] else: none(string))
      columns.add series(name, vals)
    inc i
  newDataFrameOf(columns)

proc describe*(df: DataFrame, percentiles: openArray[float] = [0.25, 0.5, 0.75],
               interpolation = QuantileMethod.Nearest): DataFrame =
  df.lazy.describe(percentiles, interpolation)

# ---------------------------------------------------------------------------
# Display config, through the environment variables Rust Polars reads
# ---------------------------------------------------------------------------

const configVars = ["POLARS_FMT_MAX_ROWS", "POLARS_FMT_MAX_COLS", "POLARS_TABLE_WIDTH",
                    "POLARS_FMT_STR_LEN"]

proc setVar(name: string, n: Option[int]) =
  if n.isSome: putEnv(name, $n.get) else: delEnv(name)

proc setTblRows*(n: int | Option[int]) =
  ## Rows shown when a frame prints (`-1`: all; `none(int)`: Polars' default, 10).
  setVar(configVars[0], toOpt(n))
proc setTblCols*(n: int | Option[int]) =
  ## Columns shown when a frame prints (`-1`: all; `none(int)`: Polars' default, 8).
  setVar(configVars[1], toOpt(n))
proc setTblWidthChars*(n: int | Option[int]) =
  ## Maximum table width in characters (`none(int)`: the terminal's width).
  setVar(configVars[2], toOpt(n))
proc setFmtStrLengths*(n: int | Option[int]) =
  ## Characters shown of each string value (`-1`: all; `none(int)`: Polars' default, 30).
  setVar(configVars[3], toOpt(n))

proc setConfig*(tblRows: int | Option[int] = none(int); tblCols: int | Option[int] = none(int);
                tblWidthChars: int | Option[int] = none(int);
                fmtStrLengths: int | Option[int] = none(int)) =
  ## Sets several display options at once, like Python's `pl.Config(...)`:
  ## `setConfig(tblRows = 12, tblCols = 10)`. Options left out are unchanged.
  if toOpt(tblRows).isSome: setTblRows(tblRows)
  if toOpt(tblCols).isSome: setTblCols(tblCols)
  if toOpt(tblWidthChars).isSome: setTblWidthChars(tblWidthChars)
  if toOpt(fmtStrLengths).isSome: setFmtStrLengths(fmtStrLengths)

proc resetConfig*() =
  ## Restores Polars' default for every display option.
  for v in configVars: delEnv(v)

type ConfigSnapshot = array[4, Option[string]]

proc saveConfig(): ConfigSnapshot =
  for i, v in configVars:
    if existsEnv(v): result[i] = some(getEnv(v))

proc restoreConfig(s: ConfigSnapshot) =
  for i, v in configVars:
    if s[i].isSome: putEnv(v, s[i].get) else: delEnv(v)

macro withConfig*(args: varargs[untyped]): untyped =
  ## Applies display options for one block, then restores the previous ones,
  ## like Python's `with pl.Config(...)`:
  ##
  ## .. code-block:: nim
  ##   withConfig(tblRows = 40):
  ##     echo season
  if args.len == 0 or args[^1].kind != nnkStmtList:
    error("withConfig expects named options and a block", args)
  let body = args[^1]
  let setCall = newCall(bindSym"setConfig")
  for i in 0 ..< args.len - 1:
    if args[i].kind != nnkExprEqExpr:
      error("withConfig options are named: withConfig(tblRows = 20)", args[i])
    setCall.add args[i]
  let saved = genSym(nskLet, "saved")
  result = quote do:
    block:
      let `saved` = saveConfig()
      try:
        `setCall`
        `body`
      finally:
        restoreConfig(`saved`)

# ---------------------------------------------------------------------------
# The str namespace
# ---------------------------------------------------------------------------

type
  StrNameSpace* = distinct Expr
    ## `e.str`: string functions, as Polars' `Expr.str`.

proc str*(e: Expr): StrNameSpace = StrNameSpace(e)
  ## String functions: `col.rider.str.toUppercase`.

proc strOp(s: StrNameSpace, op: NqStrOp, a: Expr = nil, b: Expr = nil, flag1 = false,
           flag2 = false, n = 0, ch = ' ', sep = ""): Expr =
  let e = Expr(s)
  wrap nq_expr_str(e.raw, op, (if a.isNil: nil else: a.raw), (if b.isNil: nil else: b.raw),
                   flag1, flag2, n.int64, ch.uint32, sep.cstring)

type StrArg = string | Expr

proc lenChars*(s: StrNameSpace): Expr = strOp(s, nqtLenChars)
  ## Number of characters (u32).
proc lenBytes*(s: StrNameSpace): Expr = strOp(s, nqtLenBytes)
  ## Number of bytes (u32).
proc toUppercase*(s: StrNameSpace): Expr = strOp(s, nqtToUppercase)
proc toLowercase*(s: StrNameSpace): Expr = strOp(s, nqtToLowercase)

proc stripChars*(s: StrNameSpace): Expr = strOp(s, nqtStripChars)
  ## Removes leading and trailing whitespace.
proc stripChars*(s: StrNameSpace, characters: StrArg): Expr =
  ## Removes leading and trailing characters that are in `characters`.
  strOp(s, nqtStripChars, lit(characters))
proc stripCharsStart*(s: StrNameSpace): Expr = strOp(s, nqtStripCharsStart)
proc stripCharsStart*(s: StrNameSpace, characters: StrArg): Expr =
  strOp(s, nqtStripCharsStart, lit(characters))
proc stripCharsEnd*(s: StrNameSpace): Expr = strOp(s, nqtStripCharsEnd)
proc stripCharsEnd*(s: StrNameSpace, characters: StrArg): Expr =
  strOp(s, nqtStripCharsEnd, lit(characters))
proc stripPrefix*(s: StrNameSpace, prefix: StrArg): Expr = strOp(s, nqtStripPrefix, lit(prefix))
proc stripSuffix*(s: StrNameSpace, suffix: StrArg): Expr = strOp(s, nqtStripSuffix, lit(suffix))

proc startsWith*(s: StrNameSpace, prefix: StrArg): Expr = strOp(s, nqtStartsWith, lit(prefix))
proc endsWith*(s: StrNameSpace, suffix: StrArg): Expr = strOp(s, nqtEndsWith, lit(suffix))

proc contains*(s: StrNameSpace, pattern: StrArg, literal = false, strict = true): Expr =
  ## True where the value matches the regex `pattern` (Rust regex syntax), or
  ## contains it as plain text with `literal = true`. With `strict`, an invalid
  ## regex raises; otherwise it gives null.
  strOp(s, nqtContains, lit(pattern), flag1 = literal, flag2 = strict)
proc find*(s: StrNameSpace, pattern: StrArg, literal = false, strict = true): Expr =
  ## Character index of the first match (u32), null where there is none.
  strOp(s, nqtFind, lit(pattern), flag1 = literal, flag2 = strict)
proc countMatches*(s: StrNameSpace, pattern: StrArg, literal = false): Expr =
  ## Number of non-overlapping matches (u32).
  strOp(s, nqtCountMatches, lit(pattern), flag1 = literal)
proc extract*(s: StrNameSpace, pattern: StrArg, groupIndex = 1): Expr =
  ## The `groupIndex` capture group of the first match (0: the whole match),
  ## null where there is no match.
  if groupIndex < 0: raise newException(ValueError, "extract groupIndex must not be negative")
  strOp(s, nqtExtract, lit(pattern), n = groupIndex)
proc replace*(s: StrNameSpace, pattern: StrArg, value: StrArg, literal = false, n = 1): Expr =
  ## Replaces the first `n` matches of `pattern` with `value` (`$1` refers to a
  ## capture group unless `literal`).
  strOp(s, nqtReplace, lit(pattern), lit(value), flag1 = literal, n = n)
proc replaceAll*(s: StrNameSpace, pattern: StrArg, value: StrArg, literal = false): Expr =
  ## Replaces every match of `pattern` with `value`.
  strOp(s, nqtReplaceAll, lit(pattern), lit(value), flag1 = literal)

proc slice*(s: StrNameSpace, offset: int | Expr): Expr =
  ## The characters from `offset` (negative: from the end) to the end.
  strOp(s, nqtSlice, lit(offset))
proc slice*(s: StrNameSpace, offset: int | Expr, length: int | Expr): Expr =
  ## `length` characters from `offset` (negative: from the end).
  strOp(s, nqtSlice, lit(offset), lit(length))
proc head*(s: StrNameSpace, n: int | Expr): Expr = strOp(s, nqtHead, lit(n))
  ## The first `n` characters (negative: all but the last `-n`).
proc tail*(s: StrNameSpace, n: int | Expr): Expr = strOp(s, nqtTail, lit(n))
  ## The last `n` characters (negative: all but the first `-n`).

proc padStart*(s: StrNameSpace, length: int | Expr, fillChar = ' '): Expr =
  ## Pads on the left with `fillChar` to `length` characters.
  strOp(s, nqtPadStart, lit(length), ch = fillChar)
proc padEnd*(s: StrNameSpace, length: int | Expr, fillChar = ' '): Expr =
  ## Pads on the right with `fillChar` to `length` characters.
  strOp(s, nqtPadEnd, lit(length), ch = fillChar)
proc zfill*(s: StrNameSpace, length: int | Expr): Expr =
  ## Pads with zeros on the left (after a sign) to `length` characters.
  strOp(s, nqtZfill, lit(length))
proc reverse*(s: StrNameSpace): Expr = strOp(s, nqtReverse)

proc join*(s: StrNameSpace, delimiter = "", ignoreNulls = true): Expr =
  ## Joins all values into one string, as an aggregation:
  ## `groupBy(col.rider).agg(col.race.str.join(", "))`.
  strOp(s, nqtJoin, flag1 = ignoreNulls, sep = delimiter)

proc concatStr*(exprs: openArray[Expr], separator = "", ignoreNulls = false): Expr =
  ## Concatenates expressions row by row into one string column. With
  ## `ignoreNulls = false`, a null anywhere gives null.
  let r = raws(exprs)
  wrap nq_expr_concat_str(r.firstOrNil, r.len.csize_t, separator.cstring, ignoreNulls)

proc format*(fstring: string, args: varargs[Expr]): Expr =
  ## Builds a string column from a template with `{}` placeholders, as Polars'
  ## `format`: `format("{} ({})", col.rider, col.nat)`.
  var parts: seq[Expr]
  var rest = fstring
  var used = 0
  while true:
    let i = rest.find("{}")
    if i < 0: break
    if used >= args.len:
      raise newException(ValueError, "format: more placeholders than arguments")
    if i > 0: parts.add lit(rest[0 ..< i])
    parts.add args[used]
    inc used
    rest = rest[i + 2 .. ^1]
  if used != args.len:
    raise newException(ValueError, "format: " & $args.len & " arguments for " & $used &
                       " placeholders")
  if rest.len > 0: parts.add lit(rest)
  concatStr(parts)
