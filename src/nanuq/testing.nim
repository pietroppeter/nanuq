## Assertions for tests, like Python's `polars.testing`: `assertFrameEqual`,
## `assertFrameNotEqual`, `assertSeriesEqual` and `assertSeriesNotEqual`.
## They raise `AssertionDefect` with a message naming the first difference, so
## they work in `std/unittest` tests and with plain `doAssert` style code.
##
## .. code-block:: nim
##   import nanuq, nanuq/testing
##   assertFrameEqual(df.sort("kg"), expected, checkDtypes = false)

import std/[options, strutils]
import ../nanuq

proc fail(msg: string) {.noreturn.} =
  raise newException(AssertionDefect, msg)

proc firstMismatch(l, r: Series, checkExact: bool, rtol, atol: float): Option[int] =
  ## The first row where the values differ (nulls equal nulls, NaN equals NaN).
  let df = newDataFrame(l.rename("l"), r.rename("r"))
  let a = col("l")
  let b = col("r")
  let bothNull = a.isNull and b.isNull
  let oneNull = (a.isNull and b.isNotNull) or (a.isNotNull and b.isNull)
  var differ: Expr
  if not checkExact and l.dtype.isFloat and r.dtype.isFloat:
    let nanBoth = a.isNan and b.isNan
    let close = (a - b).abs <= (lit(atol) + lit(rtol) * b.abs)
    let infSame = a == b
    differ = oneNull or ((not bothNull) and (not nanBoth) and (not close) and (not infSame)).fillNull(false)
  else:
    differ = oneNull or ((not bothNull) and (a != b)).fillNull(false)
  let idx = df.withRowIndex("__i").filter(differ).select("__i")
  if idx.height > 0: some(idx.toList("__i", int)[0])
  else: none(int)

proc cell(s: Series, i: int): string =
  let f = s.toFrame
  if f.getColumn(s.name).nullCount > 0 and f.slice(i, 1).nullCount(s.name) > 0: "null"
  else: f.getStr(s.name, i)

proc compareSeries(l, r: Series, what: string, checkDtypes, checkNames, checkExact: bool,
                   rtol, atol: float) =
  if l.len != r.len:
    fail(what & " lengths differ: " & $l.len & " != " & $r.len)
  if checkNames and l.name != r.name:
    fail(what & " names differ: " & l.name.escape & " != " & r.name.escape)
  if checkDtypes and l.dtype != r.dtype:
    fail(what & " dtypes differ: " & $l.dtype & " != " & $r.dtype)
  let (lc, rc) = (if l.dtype != r.dtype and l.dtype.isNumeric and r.dtype.isNumeric:
                    (l.castTo(Float64), r.castTo(Float64))
                  elif l.dtype != r.dtype: (l.castTo(String), r.castTo(String))
                  else: (l, r))
  let m = firstMismatch(lc, rc, checkExact, rtol, atol)
  if m.isSome:
    let i = m.get
    fail(what & " values differ at row " & $i & ": " & cell(l, i) & " != " & cell(r, i))

proc assertSeriesEqual*(left, right: Series, checkDtypes = true, checkNames = true,
                        checkOrder = true, checkExact = false, rtol = 1e-5, atol = 1e-8) =
  ## Raises `AssertionDefect` unless the Series are equal: same length, name
  ## (`checkNames`), type (`checkDtypes`) and values, nulls equal to nulls.
  ## Floats compare within `atol + rtol * abs(right)` unless `checkExact`;
  ## `checkOrder = false` sorts both first.
  var (l, r) = (left, right)
  if not checkOrder:
    l = l.toFrame.sort(l.name).getColumn(l.name)
    r = r.toFrame.sort(r.name).getColumn(r.name)
  compareSeries(l, r, "Series", checkDtypes, checkNames, checkExact, rtol, atol)

proc assertSeriesNotEqual*(left, right: Series, checkDtypes = true, checkNames = true,
                           checkOrder = true, checkExact = false, rtol = 1e-5, atol = 1e-8) =
  ## Raises `AssertionDefect` if the Series are equal (same options).
  try:
    assertSeriesEqual(left, right, checkDtypes, checkNames, checkOrder, checkExact, rtol, atol)
  except AssertionDefect:
    return
  fail("Series are equal")

proc assertFrameEqual*(left, right: DataFrame, checkRowOrder = true, checkColumnOrder = true,
                       checkDtypes = true, checkExact = false, rtol = 1e-5, atol = 1e-8) =
  ## Raises `AssertionDefect` unless the frames are equal: same columns (in
  ## order unless `checkColumnOrder = false`), types (`checkDtypes`), and rows
  ## (in order unless `checkRowOrder = false`). The message names the first
  ## difference. Floats compare as in `assertSeriesEqual`.
  let (lc, rc) = (left.columns, right.columns)
  if checkColumnOrder:
    if lc != rc: fail("DataFrame columns differ: " & $lc & " != " & $rc)
  else:
    for c in lc:
      if c notin rc: fail("DataFrame columns differ: " & c.escape & " is only on the left")
    for c in rc:
      if c notin lc: fail("DataFrame columns differ: " & c.escape & " is only on the right")
  if left.height != right.height:
    fail("DataFrame heights differ: " & $left.height & " != " & $right.height)
  var (l, r) = (left, right.select(lc))
  if not checkRowOrder:
    l = l.sort(lc)
    r = r.sort(lc)
  for c in lc:
    compareSeries(l.getColumn(c), r.getColumn(c), "DataFrame column " & c.escape, checkDtypes,
                  false, checkExact, rtol, atol)

proc assertFrameEqual*(left, right: LazyFrame, checkRowOrder = true, checkColumnOrder = true,
                       checkDtypes = true, checkExact = false, rtol = 1e-5, atol = 1e-8) =
  ## Collects both LazyFrames and compares the results.
  assertFrameEqual(left.collect, right.collect, checkRowOrder, checkColumnOrder, checkDtypes,
                   checkExact, rtol, atol)

proc assertFrameNotEqual*(left, right: DataFrame, checkRowOrder = true, checkColumnOrder = true,
                          checkDtypes = true, checkExact = false, rtol = 1e-5, atol = 1e-8) =
  ## Raises `AssertionDefect` if the frames are equal (same options).
  try:
    assertFrameEqual(left, right, checkRowOrder, checkColumnOrder, checkDtypes, checkExact, rtol, atol)
  except AssertionDefect:
    return
  fail("DataFrames are equal")
