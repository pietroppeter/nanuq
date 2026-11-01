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

import std/[macros, options, tables, sets, os, strutils, math, times, streams]
from std/unicode import runeLen, runeSubStr
import nanuq/ffi

export options  # some/none/Option, for null-aware reads and series
export tables   # Schema is an OrderedTable
export times    # DateTime, Duration and TimeInterval are temporal values
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

  GroupKind = enum gkPlain, gkDynamic, gkRolling
  LazyGroupBy* = object
    ## Grouped rows waiting for `agg`: from `groupBy`, `groupByDynamic` or `rolling`.
    lf: LazyFrame
    by: seq[Expr]
    kind: GroupKind
    index: Expr
    every, period, offset: string
    label: NqLabel
    includeBoundaries: bool
    closed: NqClosedWindow
    startBy: NqStartBy

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
    UInt64, Float32, Float64, String, Null, Date, Datetime, Duration, Time, Categorical,
    Enum, Other

  DataType* = object
    ## A Polars data type. Compare with the constants (`Int64`, `String`, ...) or
    ## with a Nim type (`dtype == Date`, `dtype == DateTime`). Dtypes Nanuq does
    ## not model yet (lists, ...) have kind `DataTypeKind.Other` and keep
    ## Polars' name.
    case kind*: DataTypeKind
    of DataTypeKind.Other: name*: string
    of DataTypeKind.Datetime, DataTypeKind.Duration:
      timeUnit*: TimeUnit   ## std/times' `TimeUnit`: Nanoseconds, Microseconds or Milliseconds
      timeZone*: string     ## IANA name, "" for none; always "" for Duration
    of DataTypeKind.Enum:
      categories*: seq[string]  ## The allowed values, in order
    else: discard

  Schema* = OrderedTable[string, DataType]
    ## Column names and data types, in column order.

  NimEnum = not bool and enum
    ## Nim enums, which map to Polars' Enum (bool is an enum in Nim).

  Date* = distinct int32
    ## A calendar date, as Polars' `Date`: days since 1970-01-01. std/times has
    ## no date without a time and a zone. Build one with `date(2026, 7, 4)`.

  TimeOfDay* = object
    ## A time of day, as Polars' `Time` (std/times' `Time` is an instant).
    ## Build one with `timeOfDay(14, 3)`.
    nanos: int64

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
  Categorical* = DataType(kind: DataTypeKind.Categorical)
    ## Strings stored as numbers, with categories found in the data (Polars'
    ## global categories). For a fixed set of values use `Enum`.

proc `==`*(a, b: DataType): bool =
  if a.kind != b.kind: return false
  case a.kind
  of DataTypeKind.Other: a.name == b.name
  of DataTypeKind.Datetime, DataTypeKind.Duration:
    a.timeUnit == b.timeUnit and a.timeZone == b.timeZone
  of DataTypeKind.Enum: a.categories == b.categories
  else: true

proc Enum*(categories: openArray[string]): DataType =
  ## Polars' `Enum`: strings from a fixed set of `categories`, ordered as given
  ## (`Enum(["Gold", "Silver", "Bronze"])`). A Nim enum type gives the same
  ## with its values: `cast(Medal)`.
  var seen = initHashSet[string]()
  for c in categories:
    if c in seen: raise newException(ValueError, "Enum categories must be unique: " & c)
    seen.incl c
  DataType(kind: DataTypeKind.Enum, categories: @categories)

proc polarsName(u: TimeUnit): string =
  ## Polars' short name: "ns", "μs", "ms".
  case u
  of Nanoseconds: "ns"
  of Microseconds: "μs"
  of Milliseconds: "ms"
  else: $u

proc checkUnit(u: TimeUnit) =
  if u notin {Nanoseconds, Microseconds, Milliseconds}:
    raise newException(ValueError, "Polars time units are Nanoseconds, Microseconds and " &
                       "Milliseconds, not " & $u)

proc `$`*(t: DataType): string =
  ## Polars' short name, e.g. "i64", "str", "datetime[μs, Europe/Rome]".
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
  of DataTypeKind.Date: "date"
  of DataTypeKind.Datetime:
    "datetime[" & polarsName(t.timeUnit) & (if t.timeZone.len > 0: ", " & t.timeZone else: "") & "]"
  of DataTypeKind.Duration: "duration[" & polarsName(t.timeUnit) & "]"
  of DataTypeKind.Time: "time"
  of DataTypeKind.Categorical: "cat"
  of DataTypeKind.Enum: "enum"
  of DataTypeKind.Other: t.name

proc isSignedInteger*(t: DataType): bool = t.kind in {DataTypeKind.Int8 .. DataTypeKind.Int64}
proc isUnsignedInteger*(t: DataType): bool = t.kind in {DataTypeKind.UInt8 .. DataTypeKind.UInt64}
proc isInteger*(t: DataType): bool = t.isSignedInteger or t.isUnsignedInteger
proc isFloat*(t: DataType): bool = t.kind in {DataTypeKind.Float32, DataTypeKind.Float64}
proc isNumeric*(t: DataType): bool = t.isInteger or t.isFloat
proc isTemporal*(t: DataType): bool = t.kind in {DataTypeKind.Date .. DataTypeKind.Time}

proc dataType*(T: typedesc, timeUnit = TimeUnit.Microseconds, timeZone = ""): DataType =
  ## The data type of a Nim type: `int8` .. `int64`, `uint8` .. `uint64`,
  ## `float32`, `float64`, `bool`, `string`, `Date`, `DateTime` (Datetime,
  ## with `timeUnit` and `timeZone`), `Duration` (with `timeUnit`) and
  ## `TimeOfDay` (Time), and Nim enums (Enum, with `$` of each value as the
  ## categories). `int` and `float` give `Int64` and `Float64`, as
  ## `series` builds them. Other types do not compile.
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
  elif T is Date: DataType(kind: DataTypeKind.Date)
  elif T is DateTime: DataType(kind: DataTypeKind.Datetime, timeUnit: timeUnit, timeZone: timeZone)
  elif T is times.Duration: DataType(kind: DataTypeKind.Duration, timeUnit: timeUnit)
  elif T is TimeOfDay: DataType(kind: DataTypeKind.Time)
  elif T is enum:
    var cats: seq[string]
    for v in T: cats.add $v
    Enum(cats)
  else: {.error: "nanuq: no Polars data type for " & $T.}

proc `==`*(t: DataType, T: typedesc): bool =
  ## `schema["born"] == Date`. `DateTime` and `Duration` match any time unit
  ## and time zone.
  when T is DateTime: t.kind == DataTypeKind.Datetime
  elif T is times.Duration: t.kind == DataTypeKind.Duration
  else: t == dataType(T)

type DtypeSpecs = object
  ## Specs for the C ABI, with the strings they point to kept alive.
  specs: seq[NqDtypeSpec]
  zones: seq[string]
  cats: seq[seq[cstring]]

proc toSpecs(ts: openArray[DataType]): DtypeSpecs =
  result.specs = newSeq[NqDtypeSpec](ts.len)
  result.zones = newSeq[string](ts.len)
  result.cats = newSeq[seq[cstring]](ts.len)
  for i, t in ts:
    if t.kind == DataTypeKind.Other:
      raise newException(InvalidOperationError, "cannot cast to " & t.name &
                         ": Nanuq does not model this dtype yet")
    result.specs[i].code = NqDtype(ord(t.kind))
    if t.kind in {DataTypeKind.Datetime, DataTypeKind.Duration}:
      checkUnit(t.timeUnit)
      result.specs[i].timeUnit = NqTimeUnit(ord(t.timeUnit))
      result.zones[i] = t.timeZone
    if t.kind == DataTypeKind.Enum:
      result.cats[i] = cstrings(t.categories)   # points into ts, alive for the call
  for i in 0 ..< ts.len:
    result.specs[i].timeZone = result.zones[i].cstring
    result.specs[i].categories = result.cats[i].firstOrNil
    result.specs[i].nCategories = result.cats[i].len.csize_t

# ---------------------------------------------------------------------------
# Temporal values: Date and TimeOfDay, and conversions to Polars' physical values
# ---------------------------------------------------------------------------

proc `==`*(a, b: Date): bool {.borrow.}
proc `<`*(a, b: Date): bool {.borrow.}
proc `<=`*(a, b: Date): bool {.borrow.}
proc `+`*(d: Date, days: int): Date = Date(d.int32 + days.int32)
  ## The date `days` days later.
proc `-`*(d: Date, days: int): Date = Date(d.int32 - days.int32)
proc `-`*(a, b: Date): int = a.int32 - b.int32
  ## Days from `b` to `a`.

proc date*(year: int, month: int | Month, day: int): Date =
  ## A calendar date: `date(2026, 7, 4)` or `date(2026, mJul, 4)`.
  let t = dateTime(year, Month(month), MonthdayRange(day), zone = utc()).toTime
  Date(floorDiv(t.toUnix, 86400).int32)

proc toDateTime*(d: Date): DateTime =
  ## Midnight UTC of `d`.
  fromUnix(d.int32.int64 * 86400).utc

proc toDate*(dt: DateTime): Date =
  ## The calendar date of `dt`, in its own zone.
  date(dt.year, dt.month, dt.monthday)

proc year*(d: Date): int = d.toDateTime.year
proc month*(d: Date): Month = d.toDateTime.month
proc monthday*(d: Date): MonthdayRange = d.toDateTime.monthday
proc `$`*(d: Date): string = d.toDateTime.format("yyyy-MM-dd")
  ## ISO 8601, as Polars prints dates: "2026-07-04".

const nanosPerDay = 86_400_000_000_000'i64

proc timeOfDay*(hour: int, minute = 0, second = 0, nanosecond = 0): TimeOfDay =
  ## A time of day: `timeOfDay(14, 3)`.
  if hour notin 0..23 or minute notin 0..59 or second notin 0..59 or
     nanosecond notin 0 ..< 1_000_000_000:
    raise newException(ValueError, "invalid time of day")
  TimeOfDay(nanos: ((hour * 60 + minute) * 60 + second).int64 * 1_000_000_000 + nanosecond)

proc hour*(t: TimeOfDay): int = int(t.nanos div 3_600_000_000_000)
proc minute*(t: TimeOfDay): int = int(t.nanos div 60_000_000_000 mod 60)
proc second*(t: TimeOfDay): int = int(t.nanos div 1_000_000_000 mod 60)
proc nanosecond*(t: TimeOfDay): int = int(t.nanos mod 1_000_000_000)
proc `==`*(a, b: TimeOfDay): bool = a.nanos == b.nanos
proc `<`*(a, b: TimeOfDay): bool = a.nanos < b.nanos
proc `<=`*(a, b: TimeOfDay): bool = a.nanos <= b.nanos

proc `$`*(t: TimeOfDay): string =
  ## As Polars prints times: "14:03:00", with a fraction when there is one.
  result = align($t.hour, 2, '0') & ":" & align($t.minute, 2, '0') & ":" &
           align($t.second, 2, '0')
  if t.nanosecond != 0:
    result.add "." & align($t.nanosecond, 9, '0').strip(leading = false, chars = {'0'})

proc toTimeOfDay*(dt: DateTime): TimeOfDay =
  ## The time of day of `dt`, in its own zone.
  timeOfDay(dt.hour, dt.minute, dt.second, dt.nanosecond)

proc unitScale(u: TimeUnit): int64 =
  ## Nanoseconds per unit.
  checkUnit(u)
  case u
  of Nanoseconds: 1
  of Microseconds: 1_000
  else: 1_000_000

proc toPhysical(d: Date): int64 = d.int32.int64
proc toPhysical(t: TimeOfDay): int64 = t.nanos
proc toPhysical(dt: DateTime, u: TimeUnit): int64 =
  let t = dt.toTime
  t.toUnix * (1_000_000_000 div unitScale(u)) + floorDiv(t.nanosecond.int64, unitScale(u))
proc toPhysical(d: times.Duration, u: TimeUnit): int64 =
  floorDiv(d.inNanoseconds, unitScale(u))

proc fromPhysical(v: int64, _: typedesc[Date], u: TimeUnit): Date = Date(v.int32)
proc fromPhysical(v: int64, _: typedesc[TimeOfDay], u: TimeUnit): TimeOfDay = TimeOfDay(nanos: v)
proc fromPhysical(v: int64, _: typedesc[DateTime], u: TimeUnit): DateTime =
  let perSec = 1_000_000_000 div unitScale(u)
  initTime(floorDiv(v, perSec), floorMod(v, perSec) * unitScale(u)).utc
proc fromPhysical(v: int64, _: typedesc[times.Duration], u: TimeUnit): times.Duration =
  initDuration(nanoseconds = v * unitScale(u))

type TemporalValue = Date | DateTime | times.Duration | TimeOfDay

proc temporalType(T: typedesc, timeUnit: TimeUnit, timeZone: string): DataType =
  dataType(T, timeUnit, timeZone)

proc physical[T](v: T, u: TimeUnit): int64 =
  when T is Date or T is TimeOfDay: toPhysical(v) else: toPhysical(v, u)

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

proc castSeries(s: Series, t: DataType): Series =
  let sp = toSpecs([t])
  wrap nq_series_cast(s.raw, sp.specs[0].unsafeAddr)

proc series*[T: NimEnum](name: string, data: openArray[T]): Series =
  ## An Enum column from Nim enum values; the categories are all values of `T`.
  var strs = newSeq[string](data.len)
  for i, x in data: strs[i] = $x
  series(name, strs).castSeries(dataType(T))

proc series*[T: NimEnum](name: string, data: openArray[Option[T]]): Series =
  ## An Enum column from Nim enum values, `none` for nulls.
  var strs = newSeq[Option[string]](data.len)
  for i, x in data:
    if x.isSome: strs[i] = some($x.get)
  series(name, strs).castSeries(dataType(T))

proc temporalSeries(name: string, vals: seq[int64], valid: seq[bool], t: DataType): Series =
  let sp = toSpecs([t])
  wrap nq_series_new_temporal(name.cstring, vals.firstOrNil, valid.firstOrNil, vals.len.csize_t,
                              sp.specs[0].unsafeAddr)

proc series*[T: TemporalValue](name: string, data: openArray[T],
                               timeUnit = TimeUnit.Microseconds, timeZone = ""): Series =
  ## A temporal column: `Date` gives Polars' Date, `DateTime` Datetime (UTC
  ## instants; naive unless `timeZone` is given), `Duration` Duration and
  ## `TimeOfDay` Time. `timeUnit` applies to DateTime and Duration.
  var vals = newSeq[int64](data.len)
  var valid = newSeq[bool](data.len)
  for i, x in data:
    vals[i] = physical(x, timeUnit)
    valid[i] = true
  temporalSeries(name, vals, valid, temporalType(T, timeUnit, timeZone))

proc series*[T: TemporalValue](name: string, data: openArray[Option[T]],
                               timeUnit = TimeUnit.Microseconds, timeZone = ""): Series =
  ## A temporal column with nulls where `data` is `none`.
  var vals = newSeq[int64](data.len)
  var valid = newSeq[bool](data.len)
  for i, x in data:
    if x.isSome:
      vals[i] = physical(x.get, timeUnit)
      valid[i] = true
  temporalSeries(name, vals, valid, temporalType(T, timeUnit, timeZone))

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
  newCall(bindSym("series", brOpen), name, vals)

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
  case DataTypeKind(k)
  of DataTypeKind.Other:
    DataType(kind: DataTypeKind.Other, name: takeString nq_df_column_dtype(df.raw, column.cstring))
  of DataTypeKind.Datetime, DataTypeKind.Duration:
    let code = nq_df_column_time_unit(df.raw, column.cstring)
    if code < 0: raiseLast()
    let u = TimeUnit(code)
    if DataTypeKind(k) == DataTypeKind.Datetime:
      DataType(kind: DataTypeKind.Datetime, timeUnit: u,
               timeZone: takeString nq_df_column_time_zone(df.raw, column.cstring))
    else:
      DataType(kind: DataTypeKind.Duration, timeUnit: u)
  of DataTypeKind.Enum:
    let n = nq_df_column_n_categories(df.raw, column.cstring)
    if n < 0: raiseLast()
    var cats = newSeq[string](n)
    for i in 0 ..< n:
      let c = nq_df_column_category(df.raw, column.cstring, i.csize_t)
      if c == nil: raiseLast()
      cats[i] = takeString(c)
    DataType(kind: DataTypeKind.Enum, categories: cats)
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
  when T is TemporalValue:
    let dt = df.dtype(column)
    if dt != T:
      raise newException(InvalidOperationError, "column '" & column & "' is " & $dt &
                         ", not " & $T)
    var buf = newSeq[int64](n)
    if not nq_df_column_physical(df.raw, column.cstring, buf.firstOrNil, valid.firstOrNil, n.csize_t):
      raiseLast()
    let u = (if dt.kind in {DataTypeKind.Datetime, DataTypeKind.Duration}: dt.timeUnit
             else: TimeUnit.Nanoseconds)
    var vals = newSeq[T](n)
    for i, x in buf:
      if valid[i]: vals[i] = fromPhysical(x, T, u)
    (vals, valid)
  elif T is int:
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
  elif T is enum and T isnot bool:
    let (strs, ok) = readColumn(df, column, string)
    valid = ok
    var byName = initTable[string, T]()
    for v in T: byName[$v] = v
    var vals = newSeq[T](n)
    for i, x in strs:
      if valid[i]:
        if x notin byName:
          raise newException(InvalidOperationError, "column '" & column & "' holds " &
                             x.escape & ", which is not a value of " & $T)
        vals[i] = byName[x]
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

proc toList*[T: int | float | bool | string | TemporalValue | NimEnum](df: DataFrame, column: string,
                                                            _: typedesc[T]): seq[T] =
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

proc toList*[T: int | float | bool | string | TemporalValue | NimEnum](df: DataFrame, column: string,
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
proc lit*[T: NimEnum](v: T): Expr = lit($v)
  ## A Nim enum value is its string: compare it with Enum columns
  ## (`col.monument == Flanders`).

proc litTemporal(v: int64, t: DataType): Expr =
  let sp = toSpecs([t])
  wrap nq_expr_lit_temporal(v, sp.specs[0].unsafeAddr)

proc lit*(v: Date): Expr = litTemporal(v.toPhysical, dataType(Date))
  ## A Date literal: `lit(date(2026, 7, 4))`.
proc lit*(v: TimeOfDay): Expr = litTemporal(v.toPhysical, dataType(TimeOfDay))
proc lit*(v: DateTime, timeUnit = TimeUnit.Microseconds, timeZone = ""): Expr =
  ## A Datetime literal holding the UTC instant of `v`: naive, unless
  ## `timeZone` is given.
  litTemporal(v.toPhysical(timeUnit), dataType(DateTime, timeUnit, timeZone))
proc lit*(v: times.Duration, timeUnit = TimeUnit.Microseconds): Expr =
  ## A Duration literal: `lit(initDuration(minutes = 4))`.
  litTemporal(v.toPhysical(timeUnit), dataType(times.Duration, timeUnit))

proc `$`*(e: Expr): string = takeString nq_expr_to_string(e.raw)

proc binary(a: Expr, op: NqBinOp, b: Expr): Expr = wrap nq_expr_binary(a.raw, op, b.raw)

template defBinOp(name, op) =
  proc name*(a, b: Expr): Expr = binary(a, op, b)
  proc name*[T: SomeNumber | string | bool | TemporalValue | NimEnum](a: Expr, b: T): Expr = binary(a, op, lit(b))
  proc name*[T: SomeNumber | string | bool | TemporalValue | NimEnum](a: T, b: Expr): Expr = binary(lit(a), op, b)

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
proc fillNull*[T: SomeNumber | string | bool | TemporalValue](e: Expr, value: T): Expr =
  e.fillNull(lit(value))

proc alias*(e: Expr, name: string): Expr = wrap nq_expr_alias(e.raw, name.cstring)

proc `cast`*(e: Expr, dtype: DataType, strict = true): Expr =
  ## Converts to `dtype`. A strict cast fails (when the query runs) on values
  ## that can't be converted; with `strict = false` they become nulls.
  ## `cast` is a Nim keyword: write `e.cast(Int32)`, or `` `cast`(e, Int32) ``.
  let sp = toSpecs([dtype])
  wrap nq_expr_cast(e.raw, sp.specs[0].unsafeAddr, strict)

proc `cast`*(e: Expr, T: typedesc, strict = true, timeUnit = TimeUnit.Microseconds,
             timeZone = ""): Expr =
  ## Converts to the data type of a Nim type: `col("a").cast(int32)`,
  ## `cast(Date)`, `cast(DateTime, timeUnit = Milliseconds, timeZone = "Europe/Rome")`.
  e.cast(dataType(T, timeUnit, timeZone), strict)

# ---------------------------------------------------------------------------
# Math functions (0.4)
# ---------------------------------------------------------------------------

proc sqrt*(e: Expr): Expr = unary(e, nqSqrt)
proc cbrt*(e: Expr): Expr = unary(e, nqCbrt)
proc exp*(e: Expr): Expr = unary(e, nqExp)
proc log10*(e: Expr): Expr = unary(e, nqLog10)
proc log1p*(e: Expr): Expr = unary(e, nqLog1p)
  ## Natural logarithm of `1 + value`.
proc sign*(e: Expr): Expr = unary(e, nqSign)
  ## -1, 0 or 1 (std/math calls it `sgn`).
proc floor*(e: Expr): Expr = unary(e, nqFloor)
proc ceil*(e: Expr): Expr = unary(e, nqCeil)
proc sin*(e: Expr): Expr = unary(e, nqSin)
proc cos*(e: Expr): Expr = unary(e, nqCos)
proc tan*(e: Expr): Expr = unary(e, nqTan)
proc cot*(e: Expr): Expr = unary(e, nqCot)
proc arcsin*(e: Expr): Expr = unary(e, nqArcSin)
proc arccos*(e: Expr): Expr = unary(e, nqArcCos)
proc arctan*(e: Expr): Expr = unary(e, nqArcTan)
proc sinh*(e: Expr): Expr = unary(e, nqSinh)
proc cosh*(e: Expr): Expr = unary(e, nqCosh)
proc tanh*(e: Expr): Expr = unary(e, nqTanh)
proc arcsinh*(e: Expr): Expr = unary(e, nqArcSinh)
proc arccosh*(e: Expr): Expr = unary(e, nqArcCosh)
proc arctanh*(e: Expr): Expr = unary(e, nqArcTanh)
proc degrees*(e: Expr): Expr = unary(e, nqDegrees)
proc radians*(e: Expr): Expr = unary(e, nqRadians)
proc isNan*(e: Expr): Expr = unary(e, nqIsNan)
  ## True for NaN. NaN is a float value, not a null: nulls give null.
proc isNotNan*(e: Expr): Expr = unary(e, nqIsNotNan)
proc isFinite*(e: Expr): Expr = unary(e, nqIsFinite)
proc isInfinite*(e: Expr): Expr = unary(e, nqIsInfinite)
proc dropNans*(e: Expr): Expr = unary(e, nqDropNans)
proc dropNulls*(e: Expr): Expr = unary(e, nqDropNulls)

proc binaryFn(a, b: Expr, op: NqBinaryFn): Expr = wrap nq_expr_binary_fn(a.raw, b.raw, op)

proc log*[T: SomeNumber | Expr](e: Expr, base: T): Expr =
  ## Logarithm to `base` (`log(2.0)` for log2).
  binaryFn(e, lit(when T is Expr: base else: base.float), nqbLog)
proc log*(e: Expr): Expr =
  ## Natural logarithm, as Polars' `log()` with its default base.
  e.log(E)
proc arctan2*[A, B: SomeNumber | Expr](y: A, x: B): Expr =
  ## Angle of the point (x, y) in radians, like Python's `pl.arctan2(y, x)`.
  binaryFn(lit(y), lit(x), nqbArctan2)
proc dot*[T: SomeNumber | Expr](e: Expr, other: T): Expr =
  ## Sum of the elementwise products (an aggregation).
  binaryFn(e, lit(other), nqbDot)
proc fillNan*[T: SomeNumber | Expr](e: Expr, value: T): Expr =
  ## Replaces NaN (not nulls) with `value`.
  binaryFn(e, lit(value), nqbFillNan)

proc clipImpl(e: Expr, lo, hi: Expr): Expr =
  wrap nq_expr_clip(e.raw, (if lo.isNil: nil else: lo.raw), (if hi.isNil: nil else: hi.raw))
proc clip*[A, B: SomeNumber | TemporalValue | Expr](e: Expr, lowerBound: A, upperBound: B): Expr =
  ## Limits values to `lowerBound..upperBound` (literals or expressions).
  clipImpl(e, lit(lowerBound), lit(upperBound))
proc clip*[A: SomeNumber | TemporalValue | Expr](e: Expr, lowerBound: A): Expr =
  ## Limits values from below. Name the bound: `clip(lowerBound = 0)`.
  clipImpl(e, lit(lowerBound), nil)
proc clip*[B: SomeNumber | TemporalValue | Expr](e: Expr, upperBound: B): Expr =
  ## Limits values from above. Name the bound: `clip(upperBound = 100)`.
  clipImpl(e, nil, lit(upperBound))

# ---------------------------------------------------------------------------
# Shift, differences, cumulative functions (0.4)
# ---------------------------------------------------------------------------

type
  NullBehavior* {.pure.} = enum
    ## What `diff` does with the first rows, which have no row above (Polars'
    ## `NullBehavior`): keep them as null, or drop them.
    Ignore, Drop

proc shift*(e: Expr, n = 1): Expr =
  ## Moves values down by `n` rows (up when negative); the rows left empty are null.
  wrap nq_expr_shift(e.raw, n.int64, nil)
proc shift*[T: SomeNumber | string | bool | TemporalValue | Expr](e: Expr, n = 1,
    fillValue: T): Expr =
  ## Like `shift`, filling the rows left empty with `fillValue`.
  let f = lit(fillValue)
  wrap nq_expr_shift(e.raw, n.int64, f.raw)
proc diff*(e: Expr, n = 1, nullBehavior = NullBehavior.Ignore): Expr =
  ## Each value minus the value `n` rows above.
  wrap nq_expr_diff(e.raw, n.int64, nullBehavior == NullBehavior.Drop)
proc pctChange*(e: Expr, n = 1): Expr =
  ## Relative change from the value `n` rows above (0.1 = +10%).
  wrap nq_expr_pct_change(e.raw, n.int64)

proc cumSum*(e: Expr, reverse = false): Expr = wrap nq_expr_cum(e.raw, nqcSum, reverse)
proc cumProd*(e: Expr, reverse = false): Expr = wrap nq_expr_cum(e.raw, nqcProd, reverse)
proc cumMin*(e: Expr, reverse = false): Expr = wrap nq_expr_cum(e.raw, nqcMin, reverse)
proc cumMax*(e: Expr, reverse = false): Expr = wrap nq_expr_cum(e.raw, nqcMax, reverse)
proc cumCount*(e: Expr, reverse = false): Expr =
  ## Running count of non-null values.
  wrap nq_expr_cum(e.raw, nqcCount, reverse)

proc rleId*(e: Expr): Expr = unary(e, nqRleId)
  ## Numbers runs of equal consecutive values: 0, 0, 1, 1, 1, 2, ...
proc peakMax*(e: Expr): Expr = unary(e, nqPeakMax)
  ## True at local maxima.
proc peakMin*(e: Expr): Expr = unary(e, nqPeakMin)
  ## True at local minima.

proc product*(e: Expr): Expr = unary(e, nqProduct)
proc mode*(e: Expr): Expr = unary(e, nqMode)
  ## Every most frequent value, in order of appearance (can be several rows).
proc argMin*(e: Expr): Expr = unary(e, nqArgMin)
  ## Row index of the first minimum.
proc argMax*(e: Expr): Expr = unary(e, nqArgMax)
  ## Row index of the first maximum.
proc skew*(e: Expr, bias = true): Expr = wrap nq_expr_moment(e.raw, false, false, bias)
proc kurtosis*(e: Expr, fisher = true, bias = true): Expr =
  ## Fisher's (excess) kurtosis by default; `fisher = false` gives Pearson's.
  wrap nq_expr_moment(e.raw, true, fisher, bias)

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
proc isIn*[T: int | float | bool | string | NimEnum](e: Expr, values: openArray[T],
                                                  nullsEqual = false): Expr =
  ## True where the value is one of `values`: `col("a").isIn([1, 3])`. Nim enum
  ## values compare as their strings.
  when T is enum and T isnot bool:
    var strs = newSeq[string](values.len)
    for i, v in values: strs[i] = $v
    let s = series("", strs)
  else:
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

proc filter*(e: Expr, predicate: Expr): Expr =
  ## The values of `e` where `predicate` is true, usually inside `agg`:
  ## `agg(col.points.filter(col.stage == "TT").sum)`. The result is shorter
  ## than the frame, so use it in an aggregation or alone in a `select`.
  wrap nq_expr_filter(e.raw, predicate.raw)

proc over*(e: Expr, partitionBy: openArray[Expr]): Expr =
  ## Computes `e` per group of `partitionBy` and gives each row its group's value.
  let b = raws(partitionBy)
  wrap nq_expr_over(e.raw, b.firstOrNil, b.len.csize_t)
proc over*(e: Expr, partitionBy: openArray[string]): Expr =
  var keys: seq[Expr]
  for n in partitionBy: keys.add col(n)
  e.over(keys)
proc over*(e: Expr, partitionBy: Expr): Expr = e.over([partitionBy])
  ## Window over one key expression: `col.x.shift.over(col.g)`.
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
  let d = toSpecs(s.dtypes).specs
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

proc `()`*(c: ColNs, names: openArray[string]): Selector =
  ## Columns by name from a list, in this order: `col(["a", "b"])` or
  ## `col(someSeq)`, as Python's `pl.col(list)`.
  Selector(names: @names)

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
  case g.kind
  of gkPlain:
    wrap nq_lf_group_by_agg(g.lf.raw, b.firstOrNil, b.len.csize_t, a.firstOrNil, a.len.csize_t)
  of gkDynamic:
    wrap nq_lf_group_by_dynamic_agg(g.lf.raw, g.index.raw, b.firstOrNil, b.len.csize_t,
                                    g.every.cstring, g.period.cstring, g.offset.cstring,
                                    g.label, g.includeBoundaries, g.closed, g.startBy,
                                    a.firstOrNil, a.len.csize_t)
  of gkRolling:
    wrap nq_lf_rolling_agg(g.lf.raw, g.index.raw, b.firstOrNil, b.len.csize_t,
                           g.period.cstring, g.offset.cstring, g.closed, a.firstOrNil,
                           a.len.csize_t)

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
  var ts = newSeq[DataType](dtypes.len)
  for i, (name, t) in dtypes:
    names[i] = name.cstring
    ts[i] = t
  let sp = toSpecs(ts)
  wrap nq_lf_cast(lf.raw, names.firstOrNil, sp.specs.firstOrNil, names.len.csize_t, strict)

proc `cast`*(lf: LazyFrame, dtype: DataType, strict = true): LazyFrame =
  ## Casts every column to `dtype`.
  let sp = toSpecs([dtype])
  wrap nq_lf_cast_all(lf.raw, sp.specs[0].unsafeAddr, strict)

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

proc dataArg(data: ptr string): (ptr uint8, csize_t) =
  ## The bytes of an in-memory source, or (nil, 0) to read a path.
  if data == nil: (nil, 0.csize_t)
  elif data[].len == 0: (cast[ptr uint8](cstring("")), 0.csize_t)
  else: (cast[ptr uint8](addr data[][0]), data[].len.csize_t)

proc selectColumns(lf: LazyFrame, columns: openArray[string]): LazyFrame =
  if columns.len == 0: return lf
  var sel = newSeq[Expr](columns.len)
  for i, c in columns: sel[i] = col(c)
  lf.select(sel)

proc scanCsvImpl(path: string, data: ptr string, separator: char, hasHeader: bool,
                 nullValues: openArray[string],
                 schemaOverrides: openArray[(string, DataType)],
                 skipRows: int, nRows: Option[int], columns: openArray[string],
                 inferSchemaLength: Option[int],
                 ignoreErrors, decimalComma, tryParseDates: bool): LazyFrame =
  let nulls = cstrings(nullValues)
  var names = newSeq[cstring](schemaOverrides.len)
  var ts = newSeq[DataType](schemaOverrides.len)
  for i, (n, t) in schemaOverrides:
    names[i] = n.cstring
    ts[i] = t
  let sp = toSpecs(ts)
  let (dp, dl) = dataArg(data)
  result = wrap nq_lf_scan_csv(path.cstring, dp, dl, separator.uint8, hasHeader,
                               nulls.firstOrNil, nulls.len.csize_t,
                               names.firstOrNil, sp.specs.firstOrNil, names.len.csize_t,
                               skipRows.csize_t, nRows.toC,
                               inferSchemaLength.toC, ignoreErrors, decimalComma,
                               tryParseDates)
  result = result.selectColumns(columns)

proc scanCsv*(path: string, separator = ',', hasHeader = true,
              nullValues: openArray[string] = [],
              schemaOverrides: openArray[(string, DataType)] = [],
              skipRows = 0, nRows: int | Option[int] = none(int),
              columns: openArray[string] = [],
              inferSchemaLength: int | Option[int] = some(100),
              ignoreErrors = false, decimalComma = false, tryParseDates = false): LazyFrame =
  ## Lazily reads a CSV file; nothing is read until the query runs. `path` may be
  ## a glob such as `"logs/*.csv"` when every file has the same columns.
  ##
  ## Fields equal to one of `nullValues` (e.g. `["NA"]`) are null; empty fields
  ## always are. `schemaOverrides` sets the dtype of some columns
  ## (`{"bears": Int64}`), the rest are inferred from the first
  ## `inferSchemaLength` rows (`none(int)`: all rows). `skipRows` skips lines
  ## before the header, `nRows` limits the rows read and `columns` keeps only
  ## those columns, in that order. With `tryParseDates`, string columns that look
  ## like ISO dates, datetimes or times become `Date`, Datetime or `TimeOfDay`
  ## columns.
  scanCsvImpl(path, nil, separator, hasHeader, nullValues, schemaOverrides, skipRows,
              toOpt(nRows), columns, toOpt(inferSchemaLength), ignoreErrors, decimalComma,
              tryParseDates)

proc readCsv*(path: string, separator = ',', hasHeader = true,
              nullValues: openArray[string] = [],
              schemaOverrides: openArray[(string, DataType)] = [],
              skipRows = 0, nRows: int | Option[int] = none(int),
              columns: openArray[string] = [],
              inferSchemaLength: int | Option[int] = some(100),
              ignoreErrors = false, decimalComma = false, tryParseDates = false): DataFrame =
  ## Reads a CSV file now: `scanCsv(...).collect`, with the same options.
  ##
  ## .. code-block:: nim
  ##   let df = readCsv("data.csv", separator = ';', nullValues = ["NA"],
  ##                    schemaOverrides = {"bears": Int64})
  scanCsv(path, separator, hasHeader, nullValues, schemaOverrides, skipRows, nRows,
          columns, inferSchemaLength, ignoreErrors, decimalComma, tryParseDates).collect

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

proc readCsv*(source: Stream, separator = ',', hasHeader = true,
              nullValues: openArray[string] = [],
              schemaOverrides: openArray[(string, DataType)] = [],
              skipRows = 0, nRows: int | Option[int] = none(int),
              columns: openArray[string] = [],
              inferSchemaLength: int | Option[int] = some(100),
              ignoreErrors = false, decimalComma = false, tryParseDates = false): DataFrame =
  ## Reads CSV from a stream (all of it, now), with the same options as reading
  ## a file: `readCsv(newStringStream("a,b\n1,2\n"))`.
  var data = source.readAll
  scanCsvImpl("", addr data, separator, hasHeader, nullValues, schemaOverrides, skipRows,
              toOpt(nRows), columns, toOpt(inferSchemaLength), ignoreErrors, decimalComma,
              tryParseDates).collect

# ---------------------------------------------------------------------------
# Parquet and IPC
# ---------------------------------------------------------------------------

type
  ParquetCompression* {.pure.} = enum
    ## Codec for `writeParquet` (Polars' `compression`). `Lz4` is Parquet's
    ## LZ4_RAW.
    Lz4, Uncompressed, Snappy, Gzip, Brotli, Zstd
  IpcCompression* {.pure.} = enum
    ## Codec for `writeIpc`.
    Uncompressed, Lz4, Zstd

proc cOrNil(s: string): cstring = (if s.len == 0: nil else: s.cstring)

proc keepRowIndex(columns: openArray[string], rowIndexName: string): seq[string] =
  ## `columns` keeps the row index, as in Polars.
  result = @columns
  if columns.len > 0 and rowIndexName.len > 0: result.insert(rowIndexName, 0)

proc scanParquetImpl(path: string, data: ptr string, nRows: Option[int],
                     columns: openArray[string], rowIndexName: string,
                     rowIndexOffset: int, lowMemory: bool): LazyFrame =
  let (dp, dl) = dataArg(data)
  result = wrap nq_lf_scan_parquet(path.cstring, dp, dl, nRows.toC, cOrNil(rowIndexName),
                                   rowIndexOffset.uint32, lowMemory)
  result = result.selectColumns(keepRowIndex(columns, rowIndexName))

proc scanParquet*(path: string, nRows: int | Option[int] = none(int),
                  columns: openArray[string] = [], rowIndexName = "",
                  rowIndexOffset = 0, lowMemory = false): LazyFrame =
  ## Lazily reads a Parquet file, or a glob of files with the same columns.
  ## `nRows` limits the rows read, `columns` keeps only those columns, and a
  ## `rowIndexName` adds a row number column first, counting from `rowIndexOffset`.
  scanParquetImpl(path, nil, toOpt(nRows), columns, rowIndexName, rowIndexOffset, lowMemory)

proc readParquet*(path: string, nRows: int | Option[int] = none(int),
                  columns: openArray[string] = [], rowIndexName = "",
                  rowIndexOffset = 0, lowMemory = false): DataFrame =
  ## Reads a Parquet file now: `scanParquet(...).collect`.
  scanParquetImpl(path, nil, toOpt(nRows), columns, rowIndexName, rowIndexOffset,
                  lowMemory).collect

proc readParquet*(source: Stream, nRows: int | Option[int] = none(int),
                  columns: openArray[string] = [], rowIndexName = "",
                  rowIndexOffset = 0, lowMemory = false): DataFrame =
  ## Reads Parquet bytes from a stream.
  var data = source.readAll
  scanParquetImpl("", addr data, toOpt(nRows), columns, rowIndexName, rowIndexOffset,
                  lowMemory).collect

proc writeParquet*(df: DataFrame, path: string, compression = ParquetCompression.Zstd,
                   compressionLevel: int | Option[int] = none(int), statistics = true,
                   rowGroupSize: int | Option[int] = none(int)) =
  ## Writes `df` as a Parquet file. `compressionLevel` applies to `Gzip` (0-9),
  ## `Brotli` (0-11) and `Zstd` (1-22); `none(int)` uses the codec's default.
  ## `statistics` writes min, max and null counts per row group, which let scans
  ## skip row groups.
  let lvl = toOpt(compressionLevel)
  let rg = toOpt(rowGroupSize)
  if lvl.isSome and compression notin {ParquetCompression.Gzip, ParquetCompression.Brotli,
                                       ParquetCompression.Zstd}:
    raise newException(ValueError, "compressionLevel needs Gzip, Brotli or Zstd, not " &
                       $compression)
  if not nq_df_write_parquet(df.raw, path.cstring, NqParquetCompression(ord(compression)),
                             (if lvl.isSome: lvl.get.int32 else: -1'i32), statistics,
                             (if rg.isSome: rg.get.int64 else: 0'i64)):
    raiseLast()

proc scanIpcImpl(path: string, data: ptr string, nRows: Option[int],
                 columns: openArray[string], rowIndexName: string,
                 rowIndexOffset: int): LazyFrame =
  let (dp, dl) = dataArg(data)
  result = wrap nq_lf_scan_ipc(path.cstring, dp, dl, nRows.toC, cOrNil(rowIndexName),
                               rowIndexOffset.uint32)
  result = result.selectColumns(keepRowIndex(columns, rowIndexName))

proc scanIpc*(path: string, nRows: int | Option[int] = none(int),
              columns: openArray[string] = [], rowIndexName = "",
              rowIndexOffset = 0): LazyFrame =
  ## Lazily reads an Arrow IPC file (Feather v2), or a glob of them. Options as
  ## in `scanParquet`.
  scanIpcImpl(path, nil, toOpt(nRows), columns, rowIndexName, rowIndexOffset)

proc readIpc*(path: string, nRows: int | Option[int] = none(int),
              columns: openArray[string] = [], rowIndexName = "",
              rowIndexOffset = 0): DataFrame =
  ## Reads an Arrow IPC file now: `scanIpc(...).collect`.
  scanIpcImpl(path, nil, toOpt(nRows), columns, rowIndexName, rowIndexOffset).collect

proc readIpc*(source: Stream, nRows: int | Option[int] = none(int),
              columns: openArray[string] = [], rowIndexName = "",
              rowIndexOffset = 0): DataFrame =
  ## Reads Arrow IPC bytes from a stream.
  var data = source.readAll
  scanIpcImpl("", addr data, toOpt(nRows), columns, rowIndexName, rowIndexOffset).collect

proc writeIpc*(df: DataFrame, path: string, compression = IpcCompression.Uncompressed) =
  ## Writes `df` as an Arrow IPC file (Feather v2).
  if not nq_df_write_ipc(df.raw, path.cstring, NqIpcCompression(ord(compression))):
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
      elif dt.kind == DataTypeKind.Datetime:   # as Python's str(datetime)
        var x = v.get
        for zeros in [".000000000", ".000000", ".000"]:
          if x.endsWith(zeros):
            x.setLen(x.len - zeros.len)
            break
        vals.add x
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
    let minMax = dt.kind notin {DataTypeKind.Null, DataTypeKind.Categorical, DataTypeKind.Enum,
                                DataTypeKind.Other}   # as Python
    let target = if asFloat: Float64 else: String
    var have: seq[bool]
    proc add(e: Expr, ok: bool, metric: string) =
      have.add ok
      if ok:
        let v =
          if dt.kind == DataTypeKind.Duration and metric notin ["count", "null_count"]:
            # Polars can't cast durations to str
            wrap nq_expr_dt(e.raw, nqdToString, nil, "polars", false, nquMicroseconds, 0)
          else: e.cast(target)
        exprs.add v.alias(metric & ":" & name)
    let c = col(name)
    add(c.count, true, "count")
    add(c.nullCount, true, "null_count")
    let temporal = dt.isTemporal
    add(c.mean, numeric or temporal or dt == Boolean, "mean")
    add(c.std, numeric, "std")
    add(c.min, minMax, "min")
    for q in percentiles:
      if temporal:
        let physicalQ = wrap(nq_expr_to_physical(c.raw)).quantile(q, interpolation).cast(dt)
        add(physicalQ, true, $q)
      else:
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

proc toPhysical*(e: Expr): Expr =
  ## The physical representation: days for Date, integers for Datetime,
  ## Duration and Time, and category indices (u32) for Categorical and Enum.
  wrap nq_expr_to_physical(e.raw)

type
  CatNameSpace* = distinct Expr
    ## `e.cat`: functions of Categorical and Enum columns, as Polars' `Expr.cat`.

proc cat*(e: Expr): CatNameSpace = CatNameSpace(e)
  ## Categorical functions: `col.medal.cat.getCategories`.

proc catOp(c: CatNameSpace, op: NqCatOp, s = "", offset = 0'i64, length = -1'i64): Expr =
  wrap nq_expr_cat(Expr(c).raw, op, s.cstring, offset, length)

proc getCategories*(c: CatNameSpace): Expr = c.catOp(nqcGetCategories)
  ## The categories as a string column: for an Enum all of them in order, for a
  ## Categorical those seen so far.
proc lenBytes*(c: CatNameSpace): Expr = c.catOp(nqcLenBytes)
  ## Length of each value in bytes (u32).
proc lenChars*(c: CatNameSpace): Expr = c.catOp(nqcLenChars)
  ## Length of each value in characters (u32).
proc startsWith*(c: CatNameSpace, prefix: string): Expr = c.catOp(nqcStartsWith, prefix)
  ## True where the value starts with `prefix`.
proc endsWith*(c: CatNameSpace, suffix: string): Expr = c.catOp(nqcEndsWith, suffix)
  ## True where the value ends with `suffix`.
proc slice*(c: CatNameSpace, offset: int, length: int | Option[int] = none(int)): Expr =
  ## Part of each value as a string: `length` characters from `offset` (negative
  ## counts from the end).
  let l = (when length is int: some(length) else: length)
  c.catOp(nqcSlice, "", offset.int64, (if l.isSome: l.get.int64 else: -1'i64))

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

proc toTitlecase*(s: StrNameSpace): Expr = strOp(s, nqtToTitlecase)
  ## "tour de france" → "Tour De France". Needs the native library built with
  ## the `nightly` feature, as the prebuilt release libraries are; otherwise it
  ## raises `InvalidOperationError` when the expression is built.

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

# ---------------------------------------------------------------------------
# Temporal cells, ranges and durations
# ---------------------------------------------------------------------------

proc `[]`*[T: TemporalValue | NimEnum](df: DataFrame, column: string, row: int, _: typedesc[T]): T =
  ## One temporal or enum cell; raises `InvalidOperationError` if it is null.
  df.slice(row, 1).toList(column, T)[0]

proc `[]`*[T: TemporalValue | NimEnum](df: DataFrame, column: string, row: int,
                             _: typedesc[Option[T]]): Option[T] =
  ## One temporal or enum cell, `none` if it is null.
  df.slice(row, 1).toList(column, Option[T])[0]

type
  ClosedWindow* {.pure.} = enum
    ## Which ends of a range are included (Polars' `ClosedWindow`).
    Left, Right, Both, None

proc toPolarsInterval*(ti: TimeInterval): string =
  ## A std/times interval in Polars' duration language: `1.months + 2.days` is
  ## "1mo2d". Mixed signs raise `ValueError`.
  let parts = [(ti.years, "y"), (ti.months, "mo"), (ti.weeks, "w"), (ti.days, "d"),
               (ti.hours, "h"), (ti.minutes, "m"), (ti.seconds, "s"),
               (ti.milliseconds, "ms"), (ti.microseconds, "us"), (ti.nanoseconds, "ns")]
  var neg, pos = false
  for (v, _) in parts:
    if v < 0: neg = true
    elif v > 0: pos = true
  if neg and pos: raise newException(ValueError, "an interval can't mix signs: " & $ti)
  if not (neg or pos): raise newException(ValueError, "an interval must not be zero")
  if neg: result.add '-'
  for (v, unit) in parts:
    if v != 0: result.add $abs(v) & unit

proc toInterval(x: string): string = x
proc toInterval(x: TimeInterval): string = toPolarsInterval(x)

proc toTu(x: TimeUnit): Option[TimeUnit] = some(x)
proc toTu(x: Option[TimeUnit]): Option[TimeUnit] = x

proc dateRange*(start, stop: Date | Expr, interval: string | TimeInterval = "1d",
                closed = ClosedWindow.Both): Expr =
  ## One date per `interval` from `start` to `stop`, as an expression for
  ## `select`: `dateRange(date(2026, 1, 1), date(2026, 12, 31), 1.days)`.
  ## Intervals are std/times intervals (`1.weeks`, `1.months`) or Polars
  ## strings ("1w", "1mo").
  let a = lit(start)
  let b = lit(stop)
  wrap nq_expr_date_range(a.raw, b.raw, toInterval(interval).cstring, NqClosedWindow(ord(closed)),
                          false, false, nquMicroseconds, "")

proc datetimeRange*(start, stop: DateTime | Expr, interval: string | TimeInterval = "1d",
                    closed = ClosedWindow.Both,
                    timeUnit: TimeUnit | Option[TimeUnit] = none(TimeUnit),
                    timeZone = ""): Expr =
  ## One datetime per `interval` from `start` to `stop`, as an expression.
  let a = lit(start)
  let b = lit(stop)
  let tu = toTu(timeUnit)
  wrap nq_expr_date_range(a.raw, b.raw, toInterval(interval).cstring, NqClosedWindow(ord(closed)),
                          true, tu.isSome, NqTimeUnit(ord(tu.get(TimeUnit.Microseconds))),
                          timeZone.cstring)

proc duration*(weeks: int | Expr = 0; days: int | Expr = 0; hours: int | Expr = 0;
               minutes: int | Expr = 0; seconds: int | Expr = 0;
               milliseconds: int | Expr = 0; microseconds: int | Expr = 0;
               nanoseconds: int | Expr = 0; timeUnit = TimeUnit.Microseconds): Expr =
  ## A Duration built from parts, each a number or an expression, as Polars'
  ## `duration`: `duration(hours = col.h, minutes = col.m)`.
  let parts = [lit(weeks), lit(days), lit(hours), lit(minutes), lit(seconds),
               lit(milliseconds), lit(microseconds), lit(nanoseconds)]
  let r = raws(parts)
  wrap nq_expr_duration(r.firstOrNil, NqTimeUnit(ord(timeUnit)))

# ---------------------------------------------------------------------------
# Parsing strings into temporal values
# ---------------------------------------------------------------------------

type
  Ambiguous* {.pure.} = enum
    ## What to do with a local time that happens twice when clocks go back
    ## (Python Polars' `ambiguous`). Write `Ambiguous.Null`: `Null` alone is
    ## the null data type.
    Raise, Earliest, Latest, Null
  NonExistent* {.pure.} = enum
    ## What to do with a local time skipped when clocks go forward (Polars'
    ## `NonExistent`).
    Null, Raise
  DurationFormat* {.pure.} = enum
    ## The two formats Polars has for durations: ISO 8601 ("PT4M23S") and its
    ## own ("4m 23s").
    Iso, Polars

proc ambiguousName(a: Ambiguous): string = ($a).toLowerAscii

proc strptime*(s: StrNameSpace, T: typedesc, format = "", strict = true, exact = true,
               cache = true, timeUnit = TimeUnit.Microseconds, timeZone = "",
               ambiguous = Ambiguous.Raise): Expr =
  ## Parses strings into `Date`, `DateTime` or `TimeOfDay` values with a chrono
  ## format (`"%d %B %Y"`; "" infers it). With `strict`, a value that doesn't
  ## parse raises; otherwise it becomes null. With `exact = false`, the format
  ## may match part of the string.
  when T isnot Date and T isnot DateTime and T isnot TimeOfDay:
    {.error: "strptime parses into Date, DateTime or TimeOfDay".}
  let sp = toSpecs([dataType(T, timeUnit, timeZone)])
  wrap nq_expr_strptime(Expr(s).raw, sp.specs[0].unsafeAddr, format.cstring, strict, exact,
                        cache, ambiguousName(ambiguous).cstring)

proc toDate*(s: StrNameSpace, format = "", strict = true, exact = true, cache = true): Expr =
  ## Parses strings into dates: `col.born.str.toDate("%d %B %Y")`.
  s.strptime(Date, format, strict, exact, cache)

proc toDatetime*(s: StrNameSpace, format = "", timeUnit = TimeUnit.Microseconds,
                 timeZone = "", strict = true, exact = true, cache = true,
                 ambiguous = Ambiguous.Raise): Expr =
  ## Parses strings into datetimes, naive unless `timeZone` is given (or the
  ## format has an offset, `%z`).
  s.strptime(DateTime, format, strict, exact, cache, timeUnit, timeZone, ambiguous)

proc toTime*(s: StrNameSpace, format = "", strict = true, cache = true): Expr =
  ## Parses strings into times of day: `str.toTime("%H:%M")`.
  s.strptime(TimeOfDay, format, strict, true, cache)

# ---------------------------------------------------------------------------
# The dt namespace
# ---------------------------------------------------------------------------

type
  DtNameSpace* = distinct Expr
    ## `e.dt`: temporal functions, as Polars' `Expr.dt`.

proc dt*(e: Expr): DtNameSpace = DtNameSpace(e)
  ## Temporal functions: `col.born.dt.year`.

proc dtOp(d: DtNameSpace, op: NqDtOp, a: Expr = nil, s = "", flag = false,
          tu = TimeUnit.Microseconds, nonExistent = 0): Expr =
  checkUnit(tu)
  wrap nq_expr_dt(Expr(d).raw, op, (if a.isNil: nil else: a.raw), s.cstring, flag,
                  NqTimeUnit(ord(tu)), nonExistent.int32)

template dtPart(name, op) =
  proc name*(d: DtNameSpace): Expr = dtOp(d, op)

dtPart(year, nqdYear)  # Year (i32).
dtPart(isoYear, nqdIsoYear)  # ISO 8601 week-numbering year (i32).
dtPart(quarter, nqdQuarter)  # Quarter, 1 to 4 (i8).
dtPart(month, nqdMonth)  # Month, 1 to 12 (i8).
dtPart(week, nqdWeek)  # ISO 8601 week, 1 to 53 (i8).
dtPart(weekday, nqdWeekday)  # Day of the week, Monday 1 to Sunday 7 (i8).
dtPart(day, nqdDay)  # Day of the month, 1 to 31 (i8).
dtPart(ordinalDay, nqdOrdinalDay)  # Day of the year, 1 to 366 (i16).
dtPart(hour, nqdHour)  # Hour, 0 to 23 (i8).
dtPart(minute, nqdMinute)  # Minute, 0 to 59 (i8).
dtPart(second, nqdSecond)  # Second, 0 to 59 (i8).
dtPart(millisecond, nqdMillisecond)  # Milliseconds of the second (i32).
dtPart(microsecond, nqdMicrosecond)  # Microseconds of the second (i32).
dtPart(nanosecond, nqdNanosecond)  # Nanoseconds of the second (i32).
dtPart(date, nqdDate)  # The date of a datetime.
dtPart(time, nqdTime)  # The time of day of a datetime.
dtPart(isLeapYear, nqdIsLeapYear)  # True in leap years.
dtPart(daysInMonth, nqdDaysInMonth)  # Number of days in the month (i8).
dtPart(monthStart, nqdMonthStart)  # The first day of the month.
dtPart(monthEnd, nqdMonthEnd)  # The last day of the month.

proc timestamp*(d: DtNameSpace, timeUnit = TimeUnit.Microseconds): Expr =
  ## Time since 1970-01-01 in `timeUnit` (i64).
  dtOp(d, nqdTimestamp, tu = timeUnit)
proc castTimeUnit*(d: DtNameSpace, timeUnit: TimeUnit): Expr =
  ## The same datetimes or durations with another time unit.
  dtOp(d, nqdCastTimeUnit, tu = timeUnit)

proc toString*(d: DtNameSpace, format: string): Expr =
  ## Formats dates, datetimes and times with a chrono format: `"%d %B %Y"`.
  dtOp(d, nqdToString, s = format)
proc toString*(d: DtNameSpace, format: DurationFormat): Expr =
  ## Formats durations, as ISO 8601 ("PT4M23S") or Polars ("4m 23s").
  dtOp(d, nqdToString, s = (if format == DurationFormat.Iso: "iso" else: "polars"))
proc strftime*(d: DtNameSpace, format: string): Expr = d.toString(format)
  ## Alias of `toString`.

proc truncate*(d: DtNameSpace, every: string | TimeInterval): Expr =
  ## Rounds down to a multiple of `every`: `truncate(1.months)` gives the first
  ## of the month.
  dtOp(d, nqdTruncate, lit(toInterval(every)))
proc round*(d: DtNameSpace, every: string | TimeInterval): Expr =
  ## Rounds to the nearest multiple of `every`.
  dtOp(d, nqdRound, lit(toInterval(every)))
proc offsetBy*(d: DtNameSpace, by: string | TimeInterval | Expr): Expr =
  ## Moves each value by a calendar-aware interval: `offsetBy(1.months)`
  ## (January 31 gives February 28), `offsetBy("-2d")`, or a string column.
  when by is Expr: dtOp(d, nqdOffsetBy, by)
  else: dtOp(d, nqdOffsetBy, lit(toInterval(by)))

proc convertTimeZone*(d: DtNameSpace, timeZone: string): Expr =
  ## The same instants on another zone's clock: `convertTimeZone("Europe/Paris")`.
  dtOp(d, nqdConvertTimeZone, s = timeZone)
proc replaceTimeZone*(d: DtNameSpace, timeZone: string, ambiguous = Ambiguous.Raise,
                      nonExistent = NonExistent.Raise): Expr =
  ## The same clock time in another zone (`""` makes it naive), which changes
  ## the instants.
  dtOp(d, nqdReplaceTimeZone, lit(ambiguousName(ambiguous)), timeZone,
       nonExistent = (if nonExistent == NonExistent.Raise: 1 else: 0))

proc combine*(d: DtNameSpace, time: Expr | TimeOfDay, timeUnit = TimeUnit.Microseconds): Expr =
  ## A datetime from a date (or datetime) and a time of day.
  dtOp(d, nqdCombine, lit(time), tu = timeUnit)

template dtTotal(name, op) =
  proc name*(d: DtNameSpace, fractional = false): Expr = dtOp(d, op, flag = fractional)

dtTotal(totalDays, nqdTotalDays)  # Whole days of a duration (i64), or fractional (f64).
dtTotal(totalHours, nqdTotalHours)  # Whole hours of a duration (i64), or fractional (f64).
dtTotal(totalMinutes, nqdTotalMinutes)  # Whole minutes of a duration.
dtTotal(totalSeconds, nqdTotalSeconds)  # Whole seconds of a duration.
dtTotal(totalMilliseconds, nqdTotalMilliseconds)  # Whole milliseconds of a duration.
dtTotal(totalMicroseconds, nqdTotalMicroseconds)  # Whole microseconds of a duration.
dtTotal(totalNanoseconds, nqdTotalNanoseconds)  # Whole nanoseconds of a duration.

# ---------------------------------------------------------------------------
# Rolling windows, exponentially weighted functions, interpolation (0.4)
# ---------------------------------------------------------------------------

type
  InterpolationMethod* {.pure.} = enum
    ## How `interpolate` fills nulls (Polars' `InterpolationMethod`).
    Linear, Nearest

proc rollingImpl(e: Expr, op: NqRolling, windowSize: int, weights: openArray[float],
                 minSamples: Option[int], center: bool, quantile = 0.0,
                 interpolation = QuantileMethod.Nearest, ddof = 1): Expr =
  if windowSize < 1: raise newException(ValueError, "rolling windowSize must be at least 1")
  if weights.len > 0 and weights.len != windowSize:
    raise newException(ValueError, "rolling weights must have windowSize values")
  let ms = minSamples.get(windowSize)
  if ms < 0: raise newException(ValueError, "rolling minSamples must not be negative")
  wrap nq_expr_rolling(e.raw, op, windowSize.csize_t, ms.csize_t, center,
                       (if weights.len > 0: weights[0].unsafeAddr else: nil),
                       weights.len.csize_t, quantile, NqQuantileMethod(ord(interpolation)),
                       ddof.uint8)

proc rollingByImpl(e: Expr, by: Expr, op: NqRolling, windowSize: string, minSamples: int,
                   closed: ClosedWindow, quantile = 0.0,
                   interpolation = QuantileMethod.Nearest, ddof = 1): Expr =
  if minSamples < 0: raise newException(ValueError, "rolling minSamples must not be negative")
  wrap nq_expr_rolling_by(e.raw, by.raw, op, windowSize.cstring, minSamples.csize_t,
                          NqClosedWindow(ord(closed)), quantile,
                          NqQuantileMethod(ord(interpolation)), ddof.uint8)

proc byExpr(by: string | Expr): Expr =
  when by is string: col(by) else: by

template defRolling(name, nameBy, op, doc) =
  proc name*(e: Expr, windowSize: int, weights: openArray[float] = [],
             minSamples: int | Option[int] = none(int), center = false): Expr =
    ## Rolling doc over the last `windowSize` rows (centred with `center`).
    ## `minSamples` non-null values are needed for a result (default `windowSize`);
    ## `weights` multiply the values of each window.
    rollingImpl(e, op, windowSize, weights, toOpt(minSamples), center)
  proc nameBy*(e: Expr, by: string | Expr, windowSize: string | TimeInterval,
               minSamples = 1, closed = ClosedWindow.Right): Expr =
    ## Rolling doc over a time window of column `by` (sorted): the window of each row
    ## spans `windowSize` (`7.days`, `"1mo"`) back from its `by` value.
    rollingByImpl(e, byExpr(by), op, toInterval(windowSize), minSamples, closed)

defRolling(rollingSum, rollingSumBy, nqrSum, "sum")
defRolling(rollingMean, rollingMeanBy, nqrMean, "mean")
defRolling(rollingMin, rollingMinBy, nqrMin, "minimum")
defRolling(rollingMax, rollingMaxBy, nqrMax, "maximum")
defRolling(rollingMedian, rollingMedianBy, nqrMedian, "median")

proc rollingStd*(e: Expr, windowSize: int, weights: openArray[float] = [],
                 minSamples: int | Option[int] = none(int), center = false, ddof = 1): Expr =
  ## Rolling standard deviation (sample, `ddof = 1`) over `windowSize` rows.
  rollingImpl(e, nqrStd, windowSize, weights, toOpt(minSamples), center, ddof = ddof)
proc rollingVar*(e: Expr, windowSize: int, weights: openArray[float] = [],
                 minSamples: int | Option[int] = none(int), center = false, ddof = 1): Expr =
  ## Rolling variance (sample, `ddof = 1`) over `windowSize` rows.
  rollingImpl(e, nqrVar, windowSize, weights, toOpt(minSamples), center, ddof = ddof)
proc rollingQuantile*(e: Expr, quantile: float, windowSize: int,
                      interpolation = QuantileMethod.Nearest, weights: openArray[float] = [],
                      minSamples: int | Option[int] = none(int), center = false): Expr =
  ## Rolling `quantile` (0 to 1) over `windowSize` rows.
  rollingImpl(e, nqrQuantile, windowSize, weights, toOpt(minSamples), center, quantile,
              interpolation)
proc rollingStdBy*(e: Expr, by: string | Expr, windowSize: string | TimeInterval,
                   minSamples = 1, closed = ClosedWindow.Right, ddof = 1): Expr =
  rollingByImpl(e, byExpr(by), nqrStd, toInterval(windowSize), minSamples, closed, ddof = ddof)
proc rollingVarBy*(e: Expr, by: string | Expr, windowSize: string | TimeInterval,
                   minSamples = 1, closed = ClosedWindow.Right, ddof = 1): Expr =
  rollingByImpl(e, byExpr(by), nqrVar, toInterval(windowSize), minSamples, closed, ddof = ddof)
proc rollingQuantileBy*(e: Expr, by: string | Expr, windowSize: string | TimeInterval,
                        quantile: float, interpolation = QuantileMethod.Nearest,
                        minSamples = 1, closed = ClosedWindow.Right): Expr =
  rollingByImpl(e, byExpr(by), nqrQuantile, toInterval(windowSize), minSamples, closed,
                quantile, interpolation)

proc ewmAlpha(com, span, halfLife, alpha: float): float =
  ## Python Polars' `_prepare_alpha`: exactly one of the four parameters.
  var given = 0
  for x in [com, span, halfLife, alpha]:
    if not x.isNaN: inc given
  if given != 1:
    raise newException(ValueError, "give exactly one of com, span, halfLife and alpha")
  if not com.isNaN:
    if com < 0: raise newException(ValueError, "com must be >= 0")
    1.0 / (1.0 + com)
  elif not span.isNaN:
    if span < 1: raise newException(ValueError, "span must be >= 1")
    2.0 / (span + 1.0)
  elif not halfLife.isNaN:
    if halfLife <= 0: raise newException(ValueError, "halfLife must be > 0")
    1.0 - exp(-ln(2.0) / halfLife)
  else:
    if alpha <= 0 or alpha > 1: raise newException(ValueError, "alpha must be in (0, 1]")
    alpha

proc ewmMean*(e: Expr, com = NaN, span = NaN, halfLife = NaN, alpha = NaN, adjust = true,
              minSamples = 1, ignoreNulls = false): Expr =
  ## Exponentially weighted mean. Give the decay as exactly one of `com` (centre
  ## of mass), `span`, `halfLife` or `alpha`, by name: `ewmMean(span = 12)`.
  wrap nq_expr_ewm(e.raw, 0, ewmAlpha(com, span, halfLife, alpha), adjust, false,
                   minSamples.csize_t, ignoreNulls)
proc ewmStd*(e: Expr, com = NaN, span = NaN, halfLife = NaN, alpha = NaN, adjust = true,
             bias = false, minSamples = 1, ignoreNulls = false): Expr =
  ## Exponentially weighted standard deviation (see `ewmMean`).
  wrap nq_expr_ewm(e.raw, 1, ewmAlpha(com, span, halfLife, alpha), adjust, bias,
                   minSamples.csize_t, ignoreNulls)
proc ewmVar*(e: Expr, com = NaN, span = NaN, halfLife = NaN, alpha = NaN, adjust = true,
             bias = false, minSamples = 1, ignoreNulls = false): Expr =
  ## Exponentially weighted variance (see `ewmMean`).
  wrap nq_expr_ewm(e.raw, 2, ewmAlpha(com, span, halfLife, alpha), adjust, bias,
                   minSamples.csize_t, ignoreNulls)

proc interpolate*(e: Expr, interpolation = InterpolationMethod.Linear): Expr =
  ## Fills nulls between two values: on a straight line, or with the nearest value.
  ## Nulls at the start and end stay null.
  wrap nq_expr_interpolate(e.raw, interpolation == InterpolationMethod.Nearest)
proc interpolateBy*(e: Expr, by: string | Expr): Expr =
  ## Linear interpolation of nulls, weighted by the distances in column `by`.
  binaryFn(e, byExpr(by), nqbInterpolateBy)

# ---------------------------------------------------------------------------
# Sorting, selecting and counting values (0.4)
# ---------------------------------------------------------------------------

type
  SearchSortedSide* {.pure.} = enum
    ## Where `searchSorted` puts a value equal to existing ones (Polars'
    ## `SearchSortedSide`).
    Any, Left, Right

proc sort*(e: Expr, descending = false, nullsLast = false): Expr =
  ## The values of `e` sorted (nulls first unless `nullsLast`).
  wrap nq_expr_sort(e.raw, descending, nullsLast, false)
proc argSort*(e: Expr, descending = false, nullsLast = false): Expr =
  ## The row indices that would sort `e`.
  wrap nq_expr_sort(e.raw, descending, nullsLast, true)
proc sortBy*(e: Expr, by: openArray[Expr], descending: openArray[bool] = []): Expr =
  ## The values of `e` in the order that sorts `by` (one or more keys).
  let b = raws(by)
  let d = @descending
  wrap nq_expr_sort_by(e.raw, b.firstOrNil, b.len.csize_t, d.firstOrNil, d.len.csize_t)
proc sortBy*(e: Expr, by: string | Expr, descending = false): Expr =
  e.sortBy([byExpr(by)], [descending])
proc reverse*(e: Expr): Expr = unary(e, nqReverse)

proc slice*(e: Expr, offset: int, length: int | Option[int] = none(int)): Expr =
  ## `length` values from `offset` (negative counts from the end), or all the rest.
  let l = toOpt(length)
  wrap nq_expr_slice(e.raw, offset.int64, (if l.isSome: l.get.int64 else: -1))
proc head*(e: Expr, n = 10): Expr =
  ## The first `n` values (Python's default is 10 too).
  e.slice(0, n)
proc tail*(e: Expr, n = 10): Expr = e.slice(-n, n)
  ## The last `n` values.

proc gather*(e: Expr, indices: Expr): Expr =
  ## The values at row `indices` (an integer expression).
  binaryFn(e, indices, nqbGather)
proc gather*(e: Expr, indices: openArray[int]): Expr =
  ## The values at `indices`: `gather([0, 2])`.
  binaryFn(e, wrap nq_expr_lit_values(series("", indices).raw), nqbGather)
proc gather*(e: Expr, index: int): Expr = binaryFn(e, lit(index), nqbGather)
proc gatherEvery*(e: Expr, n: int, offset = 0): Expr =
  ## Every `n`-th value from `offset`.
  if n < 1: raise newException(ValueError, "gatherEvery n must be at least 1")
  if offset < 0: raise newException(ValueError, "gatherEvery offset must not be negative")
  wrap nq_expr_gather_every(e.raw, n.csize_t, offset.csize_t)

proc topK*(e: Expr, k = 5): Expr =
  ## The `k` largest values, largest first.
  binaryFn(e, lit(k), nqbTopK)
proc bottomK*(e: Expr, k = 5): Expr =
  ## The `k` smallest values, smallest first.
  binaryFn(e, lit(k), nqbBottomK)
proc topKByImpl(e: Expr, k: int, by: openArray[Expr], reverse: openArray[bool],
                bottom: bool): Expr =
  if k < 0: raise newException(ValueError, "k must not be negative")
  let b = raws(by)
  let r = @reverse
  wrap nq_expr_top_k_by(e.raw, k.csize_t, b.firstOrNil, b.len.csize_t, r.firstOrNil,
                        r.len.csize_t, bottom)
proc topKBy*(e: Expr, by: openArray[Expr], k = 5, reverse: openArray[bool] = []): Expr =
  ## The values of `e` in the `k` rows where `by` is largest.
  topKByImpl(e, k, by, reverse, false)
proc topKBy*(e: Expr, by: string | Expr, k = 5, reverse = false): Expr =
  topKByImpl(e, k, [byExpr(by)], [reverse], false)
proc bottomKBy*(e: Expr, by: openArray[Expr], k = 5, reverse: openArray[bool] = []): Expr =
  ## The values of `e` in the `k` rows where `by` is smallest.
  topKByImpl(e, k, by, reverse, true)
proc bottomKBy*(e: Expr, by: string | Expr, k = 5, reverse = false): Expr =
  topKByImpl(e, k, [byExpr(by)], [reverse], true)

proc unique*(e: Expr, maintainOrder = false): Expr =
  ## The distinct values (in order of appearance with `maintainOrder`).
  unary(e, if maintainOrder: nqUniqueStable else: nqUnique)
proc argUnique*(e: Expr): Expr = unary(e, nqArgUnique)
  ## Row index of the first occurrence of each distinct value.
proc isUnique*(e: Expr): Expr = unary(e, nqIsUnique)
  ## True where the value occurs only once.
proc isDuplicated*(e: Expr): Expr = unary(e, nqIsDuplicated)
  ## True where the value occurs more than once.
proc isFirstDistinct*(e: Expr): Expr = unary(e, nqIsFirstDistinct)
proc isLastDistinct*(e: Expr): Expr = unary(e, nqIsLastDistinct)
proc uniqueCounts*(e: Expr): Expr = unary(e, nqUniqueCounts)
  ## How often each distinct value occurs, in order of appearance.
proc approxNUnique*(e: Expr): Expr = unary(e, nqApproxNUnique)
  ## Estimated number of distinct values (HyperLogLog).

proc indexOf*[T: SomeNumber | string | bool | TemporalValue | Expr](e: Expr, value: T): Expr =
  ## Index of the first occurrence of `value`, or null.
  binaryFn(e, lit(value), nqbIndexOf)
proc searchSorted*[T: SomeNumber | string | TemporalValue | Expr](e: Expr, element: T,
    side = SearchSortedSide.Any): Expr =
  ## Where `element` would go in the sorted `e` to keep it sorted.
  let op = case side
    of SearchSortedSide.Any: nqbSearchSortedAny
    of SearchSortedSide.Left: nqbSearchSortedLeft
    of SearchSortedSide.Right: nqbSearchSortedRight
  binaryFn(e, lit(element), op)

proc litValues[T](xs: openArray[T]): Expr =
  wrap nq_expr_lit_values(series("", xs).raw)
proc replaceImpl(e, old, new: Expr, strict: bool, default: Expr = nil): Expr =
  wrap nq_expr_replace(e.raw, old.raw, new.raw, strict,
                       (if default.isNil: nil else: default.raw))

type ReplaceValue = int | float | bool | string | NimEnum

proc replace*[T, U: ReplaceValue](e: Expr, old: openArray[T], new: openArray[U]): Expr =
  ## Replaces each value of `old` by the value of `new` at the same position; other
  ## values stay. The column keeps its data type.
  if old.len != new.len: raise newException(ValueError, "replace needs as many new values as old")
  replaceImpl(e, litValues(old), litValues(new), false)
proc replace*[T, U: ReplaceValue](e: Expr, mapping: openArray[(T, U)]): Expr =
  ## Replaces values with a mapping: `replace({"N": "north", "S": "south"})`.
  var olds: seq[T]
  var news: seq[U]
  for (o, n) in mapping:
    olds.add o
    news.add n
  e.replace(olds, news)
proc replace*[T, U: ReplaceValue | Expr](e: Expr, old: T, new: U): Expr =
  replaceImpl(e, lit(old), lit(new), false)
proc replaceStrict*[T, U: ReplaceValue](e: Expr, old: openArray[T], new: openArray[U]): Expr =
  ## Like `replace`, but every value must be in `old` (else the query fails with
  ## `InvalidOperationError`), and the result takes the data type of `new`.
  if old.len != new.len: raise newException(ValueError, "replace needs as many new values as old")
  replaceImpl(e, litValues(old), litValues(new), true)
proc replaceStrict*[T, U: ReplaceValue; D: ReplaceValue | Expr](e: Expr, old: openArray[T],
    new: openArray[U], default: D): Expr =
  ## Like `replaceStrict`, with `default` for the values not in `old`.
  if old.len != new.len: raise newException(ValueError, "replace needs as many new values as old")
  replaceImpl(e, litValues(old), litValues(new), true, lit(default))
proc replaceStrict*[T, U: ReplaceValue](e: Expr, mapping: openArray[(T, U)]): Expr =
  var olds: seq[T]
  var news: seq[U]
  for (o, n) in mapping:
    olds.add o
    news.add n
  e.replaceStrict(olds, news)
proc replaceStrict*[T, U: ReplaceValue; D: ReplaceValue | Expr](e: Expr,
    mapping: openArray[(T, U)], default: D): Expr =
  var olds: seq[T]
  var news: seq[U]
  for (o, n) in mapping:
    olds.add o
    news.add n
  e.replaceStrict(olds, news, default)

proc cutImpl(e: Expr, breaks: openArray[float], labels: openArray[string], leftClosed,
             quantile, allowDuplicates: bool): Expr =
  if labels.len > 0 and labels.len != breaks.len + 1:
    raise newException(ValueError, "cut needs one label more than breaks")
  let b = @breaks
  let l = cstrings(labels)
  wrap nq_expr_cut(e.raw, b.firstOrNil, b.len.csize_t, l.firstOrNil, l.len.csize_t,
                   leftClosed, quantile, allowDuplicates)
proc cut*(e: Expr, breaks: openArray[float], labels: openArray[string] = [],
          leftClosed = false): Expr =
  ## Bins values into a Categorical at `breaks`: intervals like "(0, 1]" (or
  ## "[0, 1)" with `leftClosed`), or `labels`, one more than breaks.
  cutImpl(e, breaks, labels, leftClosed, false, false)
proc qcut*(e: Expr, quantiles: openArray[float], labels: openArray[string] = [],
           leftClosed = false, allowDuplicates = false): Expr =
  ## Bins values at their `quantiles` (0 to 1), as `cut`.
  cutImpl(e, quantiles, labels, leftClosed, true, allowDuplicates)
proc qcut*(e: Expr, quantiles: int, labels: openArray[string] = [],
           leftClosed = false, allowDuplicates = false): Expr =
  ## Bins values into `quantiles` groups of equal size: `qcut(4)` for quartiles.
  if quantiles < 1: raise newException(ValueError, "qcut needs at least one bin")
  var probs: seq[float]
  for b in 1 ..< quantiles: probs.add b / quantiles
  cutImpl(e, probs, labels, leftClosed, true, allowDuplicates)

proc valueCounts*(lf: LazyFrame, column: string | Expr, sort = false, normalize = false,
                  name = ""): LazyFrame =
  ## How often each value of `column` occurs: a frame with the values and a
  ## `count` column (`proportion` with `normalize`), most frequent first with `sort`.
  let n = if name.len > 0: name elif normalize: "proportion" else: "count"
  wrap nq_lf_value_counts(lf.raw, byExpr(column).raw, sort, normalize, n.cstring)
proc valueCounts*(df: DataFrame, column: string | Expr, sort = false, normalize = false,
                  name = ""): DataFrame =
  ## How often each value of `column` occurs (see the LazyFrame version).
  df.lazy.valueCounts(column, sort, normalize, name).collect

# ---------------------------------------------------------------------------
# Horizontal functions, ranges, correlation (0.4)
# ---------------------------------------------------------------------------

type
  CorrelationMethod* {.pure.} = enum
    ## Which correlation `corr` computes (Python's `method` strings).
    Pearson, Spearman

proc horizontal(es: openArray[Expr], op: NqHorizontal, ignoreNulls = true): Expr =
  let r = raws(es)
  wrap nq_expr_horizontal(r.firstOrNil, r.len.csize_t, op, ignoreNulls)

template defHorizontal(name, op, doc) =
  proc name*(exprs: varargs[Expr, lit]): Expr =
    ## doc
    horizontal(exprs, op)
  proc name*(names: openArray[string]): Expr =
    var es: seq[Expr]
    for n in names: es.add col(n)
    horizontal(es, op)

defHorizontal(minHorizontal, nqhMin, "Row-wise minimum of the expressions (or a selector).")
defHorizontal(maxHorizontal, nqhMax, "Row-wise maximum of the expressions (or a selector).")
defHorizontal(allHorizontal, nqhAll, "Row-wise `and` of boolean expressions.")
defHorizontal(anyHorizontal, nqhAny, "Row-wise `or` of boolean expressions.")
defHorizontal(coalesce, nqhCoalesce, "The first non-null value of the expressions, row by row.")

proc sumHorizontal*(exprs: varargs[Expr, lit]): Expr =
  ## Row-wise sum of the expressions (or a selector: `sumHorizontal(col(SomeNumber))`).
  ## Nulls count as zero; see the `ignoreNulls` overload.
  horizontal(exprs, nqhSum, true)
proc sumHorizontal*(exprs: openArray[Expr], ignoreNulls: bool): Expr =
  ## Row-wise sum; with `ignoreNulls = false` a null anywhere makes the sum null.
  horizontal(exprs, nqhSum, ignoreNulls)
proc sumHorizontal*(names: openArray[string], ignoreNulls = true): Expr =
  var es: seq[Expr]
  for n in names: es.add col(n)
  horizontal(es, nqhSum, ignoreNulls)
proc meanHorizontal*(exprs: varargs[Expr, lit]): Expr =
  ## Row-wise mean of the non-null values.
  horizontal(exprs, nqhMean, true)
proc meanHorizontal*(exprs: openArray[Expr], ignoreNulls: bool): Expr =
  horizontal(exprs, nqhMean, ignoreNulls)
proc meanHorizontal*(names: openArray[string], ignoreNulls = true): Expr =
  var es: seq[Expr]
  for n in names: es.add col(n)
  horizontal(es, nqhMean, ignoreNulls)

proc intRange*(start, stop: int | Expr, step = 1, dtype = Int64): Expr =
  ## Integers from `start` up to `stop` (excluded) by `step`, as an expression:
  ## `select(intRange(0, 5))`, or `intRange(0, col.x.len)` for a row number.
  if step == 0: raise newException(ValueError, "intRange step must not be zero")
  let a = lit(start)
  let b = lit(stop)
  let sp = toSpecs([dtype])
  wrap nq_expr_int_range(a.raw, b.raw, step.int64, sp.specs[0].unsafeAddr)
proc intRange*(stop: int | Expr): Expr =
  ## Integers from 0 up to `stop` (excluded).
  intRange(0, stop)
proc linearSpace*[A, B: SomeNumber | Expr](start: A, stop: B, numSamples: int | Expr,
                                         closed = ClosedInterval.Both): Expr =
  ## `numSamples` evenly spaced floats from `start` to `stop` (ends as `closed` says).
  let a = lit(when A is Expr: start else: start.float)
  let b = lit(when B is Expr: stop else: stop.float)
  let n = lit(numSamples)
  wrap nq_expr_linear_space(a.raw, b.raw, n.raw, NqClosedInterval(ord(closed)))
proc repeat*[T: SomeNumber | string | bool | TemporalValue | Expr](value: T,
                                                                 n: int | Expr): Expr =
  ## `value` repeated `n` times: `select(repeat(1.5, 3))`. Wrap strings in `lit`
  ## (`repeat(lit("x"), 3)`): std/strutils' `repeat` takes plain strings.
  let v = lit(value)
  let k = lit(n)
  wrap nq_expr_repeat(v.raw, k.raw)

proc corr*(a, b: Expr | string, correlationMethod = CorrelationMethod.Pearson,
           propagateNans = false): Expr =
  ## Correlation of two columns, as an aggregation (Python's `pl.corr`, whose
  ## `method` is a Nim keyword): `corr("a", "b", Spearman)`.
  let x = byExpr(a)
  let y = byExpr(b)
  wrap nq_expr_corr(x.raw, y.raw, ord(correlationMethod).uint8, 1, propagateNans)
proc cov*(a, b: Expr | string, ddof = 1): Expr =
  ## Covariance of two columns, as an aggregation (Python's `pl.cov`).
  let x = byExpr(a)
  let y = byExpr(b)
  wrap nq_expr_corr(x.raw, y.raw, 2, ddof.uint8, false)

# ---------------------------------------------------------------------------
# Reshaping (0.4)
# ---------------------------------------------------------------------------

type
  ColumnNames* = object
    ## One column name or several, for parameters that take either:
    ## `index = "year"` or `index = ["year", "month"]`.
    names*: seq[string]
  PivotAgg* {.pure.} = enum
    ## How `pivot` combines the values that land in the same cell (Python's
    ## `aggregate_function` strings). `Item` requires at most one value.
    Item, First, Last, Sum, Mean, Median, Min, Max, Len

converter toColumnNames*(x: string): ColumnNames = ColumnNames(names: @[x])
converter toColumnNames*(x: seq[string]): ColumnNames = ColumnNames(names: x)
converter toColumnNames*[N: static int](x: array[N, string]): ColumnNames =
  ColumnNames(names: @x)

proc element*(): Expr = wrap nq_expr_element()
  ## The values being aggregated, in a `pivot` aggregation: `element().tanh.mean`.
proc item*(e: Expr, allowEmpty = false): Expr = wrap nq_expr_item(e.raw, allowEmpty)
  ## The single value of a group; more than one value is an error.

proc pivotAgg(a: PivotAgg): Expr =
  let el = element()
  case a
  of PivotAgg.Item: el.item(allowEmpty = true)
  of PivotAgg.First: el.first
  of PivotAgg.Last: el.last
  of PivotAgg.Sum: el.sum
  of PivotAgg.Mean: el.mean
  of PivotAgg.Median: el.median
  of PivotAgg.Min: el.min
  of PivotAgg.Max: el.max
  of PivotAgg.Len: el.len

proc pivotNames(all: seq[string], on, index, values: seq[string]): (seq[string], seq[string]) =
  ## Python's rule: index or values may be left out, and then means "the rest".
  if index.len == 0 and values.len == 0:
    raise newException(InvalidOperationError, "pivot needs index or values")
  var idx = index
  var vals = values
  if idx.len == 0:
    for c in all:
      if c notin on and c notin values: idx.add c
  elif vals.len == 0:
    for c in all:
      if c notin on and c notin index: vals.add c
  (idx, vals)

proc pivot*(lf: LazyFrame, on: ColumnNames, onColumns: DataFrame,
            index: ColumnNames = ColumnNames(), values: ColumnNames = ColumnNames(),
            aggregateFunction: PivotAgg | Expr = PivotAgg.Item, maintainOrder = true,
            separator = "_"): LazyFrame =
  ## Long to wide, lazily: the values of the `on` columns listed in `onColumns`
  ## become columns, one row per `index` value, cells from `values` combined with
  ## `aggregateFunction`. DataFrame's `pivot` finds `onColumns` itself.
  var all: seq[string]
  for k in lf.collectSchema.keys: all.add k
  let (idx, vals) = pivotNames(all, on.names, index.names, values.names)
  let o = cstrings(on.names)
  let i = cstrings(idx)
  let v = cstrings(vals)
  let agg = when aggregateFunction is Expr: aggregateFunction else: pivotAgg(aggregateFunction)
  wrap nq_lf_pivot(lf.raw, o.firstOrNil, o.len.csize_t, onColumns.raw, i.firstOrNil,
                   i.len.csize_t, v.firstOrNil, v.len.csize_t, agg.raw, maintainOrder,
                   separator.cstring)

proc pivot*(df: DataFrame, on: ColumnNames, index: ColumnNames = ColumnNames(),
            values: ColumnNames = ColumnNames(),
            aggregateFunction: PivotAgg | Expr = PivotAgg.Item, maintainOrder = true,
            sortColumns = false, separator = "_"): DataFrame =
  ## Long to wide: each distinct value of `on` becomes a column (in order of
  ## appearance, or sorted with `sortColumns`), one row per `index` value; cells
  ## hold `values` combined with `aggregateFunction` (a `PivotAgg`, or an
  ## expression on `element()`). Leave out `index` or `values` for "the rest".
  var onCols = df.lazy.select(col(on.names)).unique(maintainOrder = true)
  if sortColumns: onCols = onCols.sort(on.names)
  df.lazy.pivot(on, onCols.collect, index, values, aggregateFunction, maintainOrder,
                separator).collect

proc unpivot*(lf: LazyFrame, on: ColumnNames = ColumnNames(),
              index: ColumnNames = ColumnNames(), variableName = "variable",
              valueName = "value"): LazyFrame =
  ## Wide to long: one row per `index` value and `on` column, with the column's
  ## name in `variableName` and its value in `valueName`. `on` defaults to every
  ## column not in `index`.
  let o = cstrings(on.names)
  let i = cstrings(index.names)
  wrap nq_lf_unpivot(lf.raw, o.firstOrNil, o.len.csize_t, i.firstOrNil, i.len.csize_t,
                     variableName.cstring, valueName.cstring)
proc unpivot*(df: DataFrame, on: ColumnNames = ColumnNames(),
              index: ColumnNames = ColumnNames(), variableName = "variable",
              valueName = "value"): DataFrame =
  ## Wide to long (see the LazyFrame version).
  df.lazy.unpivot(on, index, variableName, valueName).collect

proc transpose*(df: DataFrame, includeHeader = false, headerName = "column",
                columnNames: openArray[string] = []): DataFrame =
  ## Rows become columns. With `includeHeader`, the old column names go in a first
  ## column `headerName`; new columns are `columnNames` or column_0, column_1, ...
  let n = cstrings(columnNames)
  wrap nq_df_transpose(df.raw, (if includeHeader: headerName.cstring else: nil),
                       n.firstOrNil, n.len.csize_t)

proc partitionBy*(df: DataFrame, by: ColumnNames, maintainOrder = true,
                  includeKey = true): seq[DataFrame] =
  ## Splits `df` into one frame per distinct value of the `by` columns, in order of
  ## appearance with `maintainOrder`.
  let b = cstrings(by.names)
  var n: csize_t
  let arr = nq_df_partition_by(df.raw, b.firstOrNil, b.len.csize_t, maintainOrder, includeKey,
                               n.addr)
  if arr.isNil: raiseLast()
  let parts = cast[ptr UncheckedArray[ptr NqDataFrame]](arr)
  for i in 0 ..< n.int: result.add wrap(parts[i])
  nq_df_array_free(arr, n)

proc toDummies*(df: DataFrame, columns: ColumnNames = ColumnNames(), separator = "_",
                dropFirst = false, dropNulls = false): DataFrame =
  ## One-hot encoding: each listed column (all by default) becomes one 0/1 column
  ## per distinct value, named `column_value`.
  let c = cstrings(columns.names)
  wrap nq_df_to_dummies(df.raw, c.firstOrNil, c.len.csize_t, separator.cstring, dropFirst,
                        dropNulls)

# ---------------------------------------------------------------------------
# Time-based grouping and as-of joins (0.4)
# ---------------------------------------------------------------------------

type
  Label* {.pure.} = enum
    ## Which time labels the windows of `groupByDynamic` (Polars' `Label`).
    Left, Right, DataPoint
  StartBy* {.pure.} = enum
    ## Where the first window of `groupByDynamic` starts (Polars' `StartBy`).
    WindowBound, DataPoint, Monday, Tuesday, Wednesday, Thursday, Friday, Saturday, Sunday
  AsofStrategy* {.pure.} = enum
    ## Which row of the right frame `joinAsof` takes (Polars' `AsofStrategy`).
    Backward, Forward, Nearest
  OptInterval* = object
    ## An optional interval parameter: a std/times interval or a Polars duration
    ## string; empty when not given.
    value*: string
  JoinKey* = object
    ## A join key: a column name or an expression; nil when not given.
    expr*: Expr
  AsofTolerance* = object
    ## `joinAsof`'s tolerance: an interval (`7.days`, `"1w"`) or a number.
    kind: uint8
    str: string
    i: int64
    f: float

converter toOptInterval*(x: string): OptInterval = OptInterval(value: x)
converter toOptInterval*(x: TimeInterval): OptInterval = OptInterval(value: toPolarsInterval(x))
converter toJoinKey*(x: string): JoinKey = JoinKey(expr: col(x))
converter toJoinKey*(x: Expr): JoinKey = JoinKey(expr: x)
converter toAsofTolerance*(x: string): AsofTolerance = AsofTolerance(kind: 1, str: x)
converter toAsofTolerance*(x: TimeInterval): AsofTolerance =
  AsofTolerance(kind: 1, str: toPolarsInterval(x))
converter toAsofTolerance*(x: int): AsofTolerance = AsofTolerance(kind: 2, i: x.int64)
converter toAsofTolerance*(x: float): AsofTolerance = AsofTolerance(kind: 3, f: x)

proc negated(interval: string): string =
  if interval.startsWith("-"): interval[1 .. ^1] else: "-" & interval

proc groupByDynamic*(lf: LazyFrame, indexColumn: string | Expr,
                     every: string | TimeInterval, period: OptInterval = OptInterval(),
                     offset: OptInterval = OptInterval(), includeBoundaries = false,
                     closed = ClosedWindow.Left, label = Label.Left,
                     groupBy: openArray[Expr] = [], startBy = StartBy.WindowBound): LazyGroupBy =
  ## Groups rows into time windows of the sorted `indexColumn`: a window starts
  ## every `every` (`1.months`, `"1y"`) and spans `period` (default `every`),
  ## shifted by `offset`. Follow with `agg`. `groupBy` groups within the windows.
  let p = period.value
  let o = offset.value
  LazyGroupBy(lf: lf, by: @groupBy, kind: gkDynamic, index: byExpr(indexColumn),
              every: toInterval(every), period: (if p.len == 0: toInterval(every) else: p),
              offset: (if o.len == 0: "0ns" else: o), label: NqLabel(ord(label)),
              includeBoundaries: includeBoundaries, closed: NqClosedWindow(ord(closed)),
              startBy: NqStartBy(ord(startBy)))
proc groupByDynamic*(df: DataFrame, indexColumn: string | Expr,
                     every: string | TimeInterval, period: OptInterval = OptInterval(),
                     offset: OptInterval = OptInterval(), includeBoundaries = false,
                     closed = ClosedWindow.Left, label = Label.Left,
                     groupBy: openArray[Expr] = [], startBy = StartBy.WindowBound): LazyGroupBy =
  df.lazy.groupByDynamic(indexColumn, every, period, offset, includeBoundaries, closed, label,
                         groupBy, startBy)

proc rolling*(lf: LazyFrame, indexColumn: string | Expr, period: string | TimeInterval,
              offset: OptInterval = OptInterval(), closed = ClosedWindow.Right,
              groupBy: openArray[Expr] = []): LazyGroupBy =
  ## One group per row: the rows whose `indexColumn` lies in the `period` before
  ## it (shift the window with `offset`, default minus `period`). Follow with `agg`.
  let p = toInterval(period)
  let o = offset.value
  LazyGroupBy(lf: lf, by: @groupBy, kind: gkRolling, index: byExpr(indexColumn), period: p,
              offset: (if o.len == 0: negated(p) else: o), closed: NqClosedWindow(ord(closed)))
proc rolling*(df: DataFrame, indexColumn: string | Expr, period: string | TimeInterval,
              offset: OptInterval = OptInterval(), closed = ClosedWindow.Right,
              groupBy: openArray[Expr] = []): LazyGroupBy =
  df.lazy.rolling(indexColumn, period, offset, closed, groupBy)

proc joinAsofImpl(lf, other: LazyFrame, leftOn, rightOn: Expr, byLeft, byRight: seq[string],
                  strategy: AsofStrategy, suffix: string, tolKind: uint8, tolStr: string,
                  tolInt: int64, tolFloat: float, allowExactMatches, checkSortedness,
                  coalesce: bool): LazyFrame =
  let bl = cstrings(byLeft)
  let br = cstrings(byRight)
  wrap nq_lf_join_asof(lf.raw, other.raw, leftOn.raw, rightOn.raw, bl.firstOrNil,
                       bl.len.csize_t, br.firstOrNil, br.len.csize_t, ord(strategy).uint8,
                       suffix.cstring, tolKind, tolStr.cstring, tolInt, tolFloat,
                       allowExactMatches, checkSortedness, coalesce)

proc joinAsof*(lf, other: LazyFrame, on: JoinKey = JoinKey(), leftOn: JoinKey = JoinKey(),
               rightOn: JoinKey = JoinKey(), by: ColumnNames = ColumnNames(),
               byLeft: ColumnNames = ColumnNames(), byRight: ColumnNames = ColumnNames(),
               strategy = AsofStrategy.Backward, suffix = "_right",
               tolerance: AsofTolerance = AsofTolerance(),
               allowExactMatches = true, checkSortedness = true, coalesce = true): LazyFrame =
  ## Joins each left row to the nearest right row by a sorted key (`on`, or
  ## `leftOn`/`rightOn`): the last one at or before it (`Backward`), the first at
  ## or after it (`Forward`) or the closest (`Nearest`), within `tolerance` (an
  ## interval like `7.days` or a number). `by` columns must match exactly.
  let l = (if on.expr.isNil: leftOn.expr else: on.expr)
  let r = (if on.expr.isNil: rightOn.expr else: on.expr)
  if l.isNil or r.isNil:
    raise newException(ValueError, "joinAsof needs `on`, or `leftOn` and `rightOn`")
  let bl = if by.names.len > 0: by.names else: byLeft.names
  let br = if by.names.len > 0: by.names else: byRight.names
  joinAsofImpl(lf, other, l, r, bl, br, strategy, suffix, tolerance.kind, tolerance.str,
               tolerance.i, tolerance.f, allowExactMatches, checkSortedness, coalesce)

proc joinAsof*(df, other: DataFrame, on: JoinKey = JoinKey(), leftOn: JoinKey = JoinKey(),
               rightOn: JoinKey = JoinKey(), by: ColumnNames = ColumnNames(),
               byLeft: ColumnNames = ColumnNames(), byRight: ColumnNames = ColumnNames(),
               strategy = AsofStrategy.Backward, suffix = "_right",
               tolerance: AsofTolerance = AsofTolerance(),
               allowExactMatches = true, checkSortedness = true, coalesce = true): DataFrame =
  ## As-of join (see the LazyFrame version).
  df.lazy.joinAsof(other.lazy, on, leftOn, rightOn, by, byLeft, byRight, strategy, suffix,
                   tolerance, allowExactMatches, checkSortedness, coalesce).collect
