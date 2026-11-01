## Reading and writing SQLite databases, like Python Polars' `read_database`,
## `read_database_uri` and `write_database`. It uses the
## `db_connector <https://github.com/nim-lang/db_connector>`_ package (the
## database modules that left Nim's standard library), an optional dependency:
## only this module needs it.
##
## .. code-block:: nim
##   import nanuq, nanuq/database
##   import db_connector/db_sqlite
##
##   let db = open("bears.db", "", "", "")
##   newDataFrame(series("bear", @["Ada", "Bo"]), series("kg", @[410, 380]))
##     .writeDatabase("bears", db)
##   echo readDatabase("select * from bears where kg > 400", db)
##   db.close
##
## Column types come from the values SQLite returns (INTEGER, REAL, TEXT, BLOB),
## or, for a column of only nulls, from its declared type.

import std/[options, strutils]
import pkg/db_connector/db_sqlite
import pkg/db_connector/sqlite3
import ../nanuq

export db_sqlite.DbConn

type
  IfTableExists* {.pure.} = enum
    ## What `writeDatabase` does when the table exists (Python's `if_table_exists`).
    Fail, Replace, Append

  Cell = object
    kind: int32   # SQLITE_INTEGER, SQLITE_FLOAT, SQLITE_TEXT, SQLITE_BLOB, SQLITE_NULL
    i: int64
    f: float
    s: string

proc check(db: DbConn, rc: int32) =
  if rc != SQLITE_OK and rc != SQLITE_DONE and rc != SQLITE_ROW:
    raise newException(IOError, "SQLite: " & $errmsg(db))

proc declared(decl: string): DataType =
  ## SQLite's type affinity rules, for columns with only nulls.
  let d = decl.toUpperAscii
  if "INT" in d: Int64
  elif "REAL" in d or "FLOA" in d or "DOUB" in d: Float64
  elif "BLOB" in d: Binary
  else: String

proc toSeries(name: string, cells: seq[Cell], decl: string): Series =
  var kinds: set[int8]
  for c in cells:
    if c.kind != SQLITE_NULL: kinds.incl c.kind.int8
  if kinds.len == 0:
    let t = declared(decl)
    let nulls = series(name, newSeq[Option[string]](cells.len))
    return (if t == Null or t == String: nulls else: nulls.castTo(t))
  if kinds == {SQLITE_INTEGER.int8}:
    var v = newSeq[Option[int]](cells.len)
    for i, c in cells:
      if c.kind == SQLITE_INTEGER: v[i] = some(c.i.int)
    series(name, v)
  elif kinds <= {SQLITE_INTEGER.int8, SQLITE_FLOAT.int8}:
    var v = newSeq[Option[float]](cells.len)
    for i, c in cells:
      if c.kind == SQLITE_INTEGER: v[i] = some(c.i.float)
      elif c.kind == SQLITE_FLOAT: v[i] = some(c.f)
    series(name, v)
  elif kinds == {SQLITE_BLOB.int8}:
    var v = newSeq[Option[string]](cells.len)
    for i, c in cells:
      if c.kind == SQLITE_BLOB: v[i] = some(c.s)
    series(name, v, Binary)
  else:
    var v = newSeq[Option[string]](cells.len)
    for i, c in cells:
      case c.kind
      of SQLITE_INTEGER: v[i] = some($c.i)
      of SQLITE_FLOAT: v[i] = some($c.f)
      of SQLITE_NULL: discard
      else: v[i] = some(c.s)
    series(name, v)

proc readDatabase*(query: string, connection: DbConn,
                   schemaOverrides: openArray[(string, DataType)] = []): DataFrame =
  ## Runs `query` on an open SQLite connection and returns the rows as a frame.
  ## INTEGER columns become Int64, REAL (or mixed numbers) Float64, TEXT
  ## String, BLOB Binary; `schemaOverrides` casts some columns.
  var stmt: PStmt
  check(connection, prepare_v2(connection, query.cstring, query.len.cint, stmt, nil))
  try:
    let n = column_count(stmt).int
    var names = newSeq[string](n)
    var decls = newSeq[string](n)
    var cols = newSeq[seq[Cell]](n)
    for j in 0 ..< n:
      names[j] = $column_name(stmt, j.int32)
      let d = column_decltype(stmt, j.int32)
      decls[j] = (if d == nil: "" else: $d)
    while true:
      let rc = step(stmt)
      if rc == SQLITE_DONE: break
      if rc != SQLITE_ROW: check(connection, rc)
      for j in 0 ..< n:
        var c = Cell(kind: column_type(stmt, j.int32))
        case c.kind
        of SQLITE_INTEGER: c.i = column_int64(stmt, j.int32)
        of SQLITE_FLOAT: c.f = column_double(stmt, j.int32)
        of SQLITE_TEXT: c.s = $column_text(stmt, j.int32)
        of SQLITE_BLOB:
          let len = column_bytes(stmt, j.int32)
          c.s = newString(len)
          if len > 0: copyMem(addr c.s[0], column_blob(stmt, j.int32), len)
        else: discard
        cols[j].add c
    var series: seq[Series]
    for j in 0 ..< n: series.add toSeries(names[j], cols[j], decls[j])
    result = newDataFrame(series)
  finally:
    discard finalize(stmt)
  if schemaOverrides.len > 0: result = result.cast(schemaOverrides)

proc openUri(uri: string): DbConn =
  for prefix in ["sqlite:///", "sqlite://"]:
    if uri.startsWith(prefix):
      return open(uri[prefix.len .. ^1], "", "", "")
  raise newException(ValueError, "only sqlite:// URIs are supported, not " & uri)

proc readDatabaseUri*(query: string, uri: string,
                      schemaOverrides: openArray[(string, DataType)] = []): DataFrame =
  ## `readDatabase` on a database given by URI (`sqlite:///path/to/file.db`),
  ## opened and closed for the query.
  let db = openUri(uri)
  try: readDatabase(query, db, schemaOverrides)
  finally: db_sqlite.close(db)

proc sqlType(t: DataType): string =
  if t.isInteger or t == Boolean: "INTEGER"
  elif t.isFloat: "REAL"
  elif t == Binary: "BLOB"
  else: "TEXT"

proc quoteIdent(s: string): string = "\"" & s.replace("\"", "\"\"") & "\""

proc writeDatabase*(df: DataFrame, tableName: string, connection: DbConn,
                    ifTableExists = IfTableExists.Fail): int =
  ## Writes the rows of `df` to the SQLite table `tableName`, creating it with
  ## column types from the frame (INTEGER, REAL, BLOB, TEXT; dates and times as
  ## ISO text). Returns the number of rows written.
  let exists = connection.getValue(sql"select count(*) from sqlite_master where type = 'table' and name = ?",
                                   tableName) != "0"
  if exists:
    case ifTableExists
    of IfTableExists.Fail:
      raise newException(ValueError, "table " & tableName & " already exists; use ifTableExists = Replace or Append")
    of IfTableExists.Replace:
      connection.exec(sql("drop table " & quoteIdent(tableName)))
    of IfTableExists.Append: discard
  let names = df.columns
  if not exists or ifTableExists == IfTableExists.Replace:
    var defs: seq[string]
    for n in names: defs.add quoteIdent(n) & " " & sqlType(df.dtype(n))
    connection.exec(sql("create table " & quoteIdent(tableName) & " (" & defs.join(", ") & ")"))
  # read every column once, typed for binding
  type Col = object
    kind: int
    ints: seq[Option[int]]
    floats: seq[Option[float]]
    strs: seq[Option[string]]
  var cols: seq[Col]
  for n in names:
    let t = df.dtype(n)
    if t.isInteger or t == Boolean:
      cols.add Col(kind: 0, ints: (if t == Boolean: df.select(col(n).cast(Int64)).toList(n, Option[int])
                                   else: df.toList(n, Option[int])))
    elif t.isFloat or t.kind == DataTypeKind.Decimal:
      cols.add Col(kind: 1, floats: df.toList(n, Option[float]))
    else:
      cols.add Col(kind: (if t == Binary: 3 else: 2), strs: df.toList(n, Option[string]))
  var marks = newSeq[string](names.len)
  for i in 0 ..< names.len: marks[i] = "?"
  var qn: seq[string]
  for n in names: qn.add quoteIdent(n)
  let ps = connection.prepare("insert into " & quoteIdent(tableName) & " (" & qn.join(", ") &
                              ") values (" & marks.join(", ") & ")")
  connection.exec(sql"begin")
  try:
    for r in 0 ..< df.height:
      for j, c in cols:
        let idx = j + 1
        case c.kind
        of 0:
          if c.ints[r].isSome: ps.bindParam(idx, c.ints[r].get) else: ps.bindNull(idx)
        of 1:
          if c.floats[r].isSome: ps.bindParam(idx, c.floats[r].get) else: ps.bindNull(idx)
        of 3:
          if c.strs[r].isSome: ps.bindParam(idx, c.strs[r].get.toOpenArrayByte(0, c.strs[r].get.high))
          else: ps.bindNull(idx)
        else:
          if c.strs[r].isSome: ps.bindParam(idx, c.strs[r].get) else: ps.bindNull(idx)
      if step(ps.PStmt) != SQLITE_DONE: dbError(connection)
      discard reset(ps.PStmt)
    connection.exec(sql"commit")
  except CatchableError as e:
    connection.exec(sql"rollback")
    raise e
  finally:
    finalize(ps)
  df.height
