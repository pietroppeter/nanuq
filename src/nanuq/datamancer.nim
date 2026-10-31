## Converting DataFrames between Nanuq and
## `Datamancer <https://github.com/SciNim/Datamancer>`_, the pure Nim dataframe
## that ggplotnim plots. Like Python Polars' `to_pandas` / `from_pandas`, the
## data is copied. Datamancer is an optional dependency: only this module
## needs it.
##
## .. code-block:: nim
##   import nanuq, nanuq/[datasets, datamancer]
##   import ggplotnim
##
##   let df = penguins().dropNulls.toDatamancer
##   ggplot(df, aes("flipper_length_mm", "body_mass_g", color = "species")) +
##     geom_point() + ggsave("penguins.png")
##
## Both libraries define `DataFrame`, so qualify it when you name the type.

import std/options
import pkg/datamancer as dmc
import ../nanuq

proc column[T](df: nanuq.DataFrame, name: string, _: typedesc[T]): Column =
  ## A typed column, or an object column with `null` entries if it has nulls.
  if df.hasNulls(name):
    var values = newSeq[Value]()
    for v in df.toList(name, Option[T]):
      values.add(if v.isSome: %~ v.get else: null())
    toColumn(values)
  else:
    toColumn(df.toList(name, T))

proc toDatamancer*(df: nanuq.DataFrame): dmc.DataFrame =
  ## Copies every column, in order: integers become `int` columns, floats
  ## `float`, booleans `bool`, strings `string`, and any other dtype `string`
  ## as Polars formats it. A column with nulls becomes an object column whose
  ## missing entries are Datamancer `null` values.
  result = dmc.newDataFrame(df.width)
  for name in df.columns:
    let dt = df.dtype(name)
    result[name] =
      if dt.isInteger: column(df, name, int)
      elif dt.isFloat: column(df, name, float)
      elif dt == Boolean: column(df, name, bool)
      else: column(df, name, string)
  result.len = df.height

proc objectSeries(name: string, values: seq[Value]): Series =
  ## An object column of one value kind (plus nulls) as a Series with nulls.
  var kind = VNull
  for v in values:
    if v.kind != VNull:
      if kind == VNull: kind = v.kind
      elif v.kind != kind:
        raise newException(NanuqError, "cannot convert Datamancer column '" & name &
          "': it mixes " & $kind & " and " & $v.kind & " values")
  template opts(T, get): untyped =
    var s: seq[Option[T]]
    for v in values:
      s.add(if v.kind == VNull: none(T) else: some(get(v)))
    series(name, s)
  case kind
  of VInt: opts(int, toInt)
  of VFloat: opts(float, toFloat)
  of VBool: opts(bool, toBool)
  of VString, VNull: opts(string, toStr)
  else:
    raise newException(NanuqError, "cannot convert Datamancer column '" & name &
      "' holding " & $kind & " values")

proc fromDatamancer*(dm: dmc.DataFrame): nanuq.DataFrame =
  ## Copies every column back, in order: `int` to i64, `float` to f64, `bool`,
  ## `string` to str, constant columns repeated to the frame's length, and
  ## object columns of one value kind (plus `null` values) to that dtype with
  ## nulls. Other columns raise `NanuqError`.
  var cols: seq[Series]
  for name in dm.getKeys:
    let c = dm[name]
    case c.kind
    of colInt: cols.add series(name, c.toTensor(int).toSeq1D)
    of colFloat: cols.add series(name, c.toTensor(float).toSeq1D)
    of colBool: cols.add series(name, c.toTensor(bool).toSeq1D)
    of colString: cols.add series(name, c.toTensor(string).toSeq1D)
    of colObject, colConstant: cols.add objectSeries(name, c.toTensor(Value).toSeq1D)
    else:
      raise newException(NanuqError, "cannot convert Datamancer column '" & name &
        "' of kind " & $c.kind)
  nanuq.newDataFrame(cols)
