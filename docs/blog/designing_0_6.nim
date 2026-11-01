import nimib
import std/os
import ../nanuqtheme

nbInit
nb.title = "Designing Nanuq 0.6"
# dated slug for the dev log (module names can't start with a digit)
nb.doc.filename = nb.doc.filename.parentDir / "2026-11-01-designing-0-6.html"
nb.useNanuqTheme(
  titleHtml = "Designing Nanuq <em>0.6</em>",
  eyebrow = "Nanuq dev log · 1 November 2026",
  epigraph = "The streaming engine, saved query plans, bytes and decimals, Arrow memory shared with Nim, Excel and SQLite: the API choices 0.6 had to make, and what we picked.",
  meta = "API design · runs on Nanuq 0.6 · rendered with nimib",
  summary = "The API decisions behind Nanuq 0.6: streaming and sinks, plan serialization, Binary and Decimal, the Arrow C Data Interface, Excel, SQLite, testing helpers, and what the book still asked for.",
)

nbText: """
Nanuq 0.6 is the release the roadmap called "engine and edges". The engine part is
Polars' streaming engine: queries that run in batches and write straight to files
without holding the result in memory. The edges are the places where data enters and
leaves: Arrow memory shared with other libraries (and with Nim code, without copying),
Excel workbooks, SQLite databases, saved query plans, and two new column types for
raw bytes and exact decimals.

It came in nine OpenSpec changes, two of which are the functions the Nanuq Book ports
still missed. Two ideas from the plan did not make it, and the last section says why.
Every snippet below runs, on a few made-up rows about bear sightings.
"""

nbCode:
  import std/[options, os, tables]
  import nanuq
  let tmp = getTempDir() / "designing-0-6"
  createDir tmp
  let sightings = newDataFrame:
    bear: ["Ada", "Bo", "Ada", "Cy", "Bo", "Ada"]
    region: ["north", "south", "north", "east", "south", "east"]
    kg: [412.5, 380.0, 415.0, 290.5, 377.5, 418.0]
    day: [1, 1, 2, 2, 3, 3]
  echo sightings

nbText: """
## 1. One `collect`, with an engine

Python spells the engine as a string: `lf.collect(engine="streaming")`. Nanuq takes an
enum, `Engine.Auto`, `Engine.Streaming` or `Engine.InMemory`, as a second argument of
the `collect` we already had. A typo is a compile error, and the default stays the
one-argument `collect`. `collectAll` runs several queries together, so Polars can
share the parts they have in common.

There is no `profile`: py-polars 2.0 removed `LazyFrame.profile`, as its timings were
misleading under the streaming engine, and the Polars Nanuq now builds on (see the
last section) no longer has it. Calling it is a compile-time error that says so.
"""

nbCode:
  let byBear = sightings.lazy.groupBy("bear").agg(col("kg").mean).sort("bear")
  echo byBear.collect(Engine.Streaming)

nbText: """
## 2. Sinks: a path or a `PartitionBy`, and `lazy` as a static flag

A sink writes a query's result to a file while it streams: `sinkParquet`, `sinkIpc`,
`sinkCsv`, `sinkNdjson`. Python's target is either a path or a `PartitionBy` object
that splits the output into Hive-style folders (`region=north/...`). Nanuq does the
same with a `string | PartitionBy` type class, so there is one proc per format, not two.

Python's sinks also take `lazy=True`, which returns the sink as a LazyFrame instead of
running it, so `collect_all` can run several sinks in one go. The return type depends
on the flag (nothing, or a LazyFrame), which a Nim proc can't do with a runtime bool.
So `lazy` is a `static bool` and the return type is `auto`: `sinkCsv(path)` is a
statement, `sinkCsv(path, lazy = true)` an expression.
"""

nbCode:
  sightings.lazy.filter(col("kg") > 400).sinkCsv(tmp / "heavy.csv")
  echo readFile(tmp / "heavy.csv")
  sightings.lazy.sinkParquet(PartitionBy(basePath: tmp / "by_region", key: @["region"]))
  for kind, path in walkDir(tmp / "by_region", relative = true): echo path

nbText: """
## 3. Saving a query plan

`serialize` turns a LazyFrame (or an expression, via `meta.serialize`) into bytes or
JSON; `deserialize` turns it back. In Python the bytes are `bytes`. In Nanuq they are a
`string`, Nim's usual byte container, which writes to a file or a socket as is. The
format is `SerializationFormat.Binary` (Polars' compact format) or `Json`. As in Python,
a plan holds the data of in-memory frames, so a plan over `scanParquet` is small and a
plan over a DataFrame carries the rows with it.

The rest of the `meta` namespace came along: `eq` and `ne` (are two expressions the
same?), `pop`, `isColumnSelection`, `isLiteral`, `isRegexProjection` and `treeFormat`.
"""

nbCode:
  let plan = sightings.lazy.filter(col("bear") == "Ada").select("day", "kg")
  let saved = plan.serialize(SerializationFormat.Json)
  echo saved.len, " bytes of JSON"
  echo LazyFrame.deserialize(saved, SerializationFormat.Json).collect
  echo (col("kg") * 2).meta.eq(col("kg") * 2)

nbText: """
## 4. Bytes and decimals

A `Binary` column holds raw bytes. A Nim `string` already is a byte sequence (it may
hold zeros and invalid UTF-8), so binary values go in and out as strings:
`series("raw", @["\x00\x01", "ok"], Binary)`, and `toList(string)` reads them back. The
`bin` namespace has `contains`, `startsWith`, `endsWith`, `encode`, `decode` and
`size`; `str.encode` goes the other way.

`Decimal(precision, scale)` is an exact decimal type, for money and the like. Nim has
no decimal type in its standard library, so Nanuq reads decimal values as `string`
(exact) or `float` (convenient), and builds them by casting or with `str.toDecimal`.
A Decimal type prints as Nanuq code, `Decimal(10, 2)`, like the other types since 0.5.
"""

nbCode:
  let prices = newDataFrame(series("price", @["12.50", "3.99", "100.00"]))
    .select(col("price").str.toDecimal(2))
  echo prices.schema
  echo prices["price", 0, string]
  echo newDataFrame(series("tag", @["polar"])).select(col("tag").str.encode(BinaryEncoding.Hex))

nbText: """
## 5. Arrow memory, shared with Nim

Polars keeps each column in Arrow format. The Arrow C Data Interface is the standard
way to hand such a column to another library without copying it: two C structs, a
schema and an array, each with a `release` callback that frees it. Nanuq now speaks
it in both directions: `toArrow`/`fromArrow` for Series (Python's `to_arrow` and
`pl.from_arrow`), and an `ArrowArrayStream` for whole frames.

The Nim side has to answer one question: who frees the memory? We wrapped the two
structs in `ArrowExport`, an object with a destructor that calls `release` and a
`=copy` that is a compile error, so it can be moved but never freed twice. A consumer
that takes the array over sets its `release` to nil, as the Arrow spec says, and the
destructor then skips it.

The same machinery gives Nim code direct access to a column: `view(T)` returns a
`ColumnView[T]` over Polars' own buffer, with `[]`, `len`, `items` and `toOpenArray`.
The type must match exactly (`int` for Int64, `float32` for Float32) and the column
must have no nulls; otherwise `view` raises and points at `toList`. The view holds the
exported buffer, so it stays valid even if the Series goes away first.
"""

nbCode:
  let kg = sightings.view("kg", float)
  var total = 0.0
  for x in kg: total += x
  echo kg.len, " values, total ", total
  var ex = sightings.getColumn("day").toArrow
  echo ex.schema.format, " ", ex.array.length
  echo fromArrow(ex, name = "day again")

nbText: """
`mapElements` uses views when it can. In 0.5 each batch was copied into a Nim `seq`
and the results copied back; now a numeric column without nulls whose type matches the
proc's argument is read in place. On the 1,000,000-row benchmark in `benchmarks/`, the
int → float callback went from 14-18 ms to 5 ms, against 2-4 ms for the native
expression and 128-187 ms for py-polars' `map_elements`. Strings and structs still
copy: they need a Nim `string` or object per value.

## 6. Excel without Python

Python Polars reads Excel through one of three Python packages (fastexcel, openpyxl,
xlsx2csv) and writes it through XlsxWriter. Nanuq has no Python, so it uses two
Rust crates compiled into the Nanuq library: calamine to read and rust_xlsxwriter to
write. They add no system dependency and nothing to install.

`readExcel(path, sheetName = "", sheetId = 1, hasHeader, headerRow, skipRows, columns,
schemaOverrides)` follows Python's names, with fastexcel's meaning: `skipRows` skips
rows after the header row, which the book found on a workbook with an empty row under
its header. Excel cells carry little type information,
so the column types are inferred: all booleans give Boolean, whole numbers Int64, other
numbers Float64, dates at midnight Date, other dates Datetime, anything else String.
`schemaOverrides` fixes the rest. `readExcelSheets` reads every sheet into an ordered
table (Python's `sheet_id=0`). `writeExcel` writes one sheet with a bold header, dates
formatted as dates and optional autofit, which covers the book's uses; XlsxWriter's
charts, conditional formats and tables are not there.
"""

nbCode:
  sightings.writeExcel(tmp / "sightings.xlsx", worksheet = "Sightings")
  echo readExcel(tmp / "sightings.xlsx", sheetName = "Sightings").head(3)

nbText: """
## 7. SQLite, as an optional module

Python's `read_database` takes a connection from any of a dozen database libraries.
Nim's equivalent is `db_connector`, which covers SQLite, PostgreSQL and MySQL. We
started with SQLite, the one databases chapters use for examples, in an optional module
`nanuq/database`, so the core library does not depend on db_connector:

- `readDatabase(query, connection, schemaOverrides)` and
  `readDatabaseUri(query, "sqlite:///path")` read a query result. Column types come from
  the values (SQLite is dynamically typed), falling back on the declared column type.
- `writeDatabase(df, tableName, connection, ifTableExists)` creates the table and inserts
  the rows in one transaction, with `IfTableExists.Fail`, `Replace` or `Append`
  (Python's `if_table_exists` strings).
"""

nbCode:
  import nanuq/database
  import db_connector/db_sqlite
  let db = open(tmp / "bears.db", "", "", "")
  discard sightings.writeDatabase("sightings", db, IfTableExists.Replace)
  echo readDatabase("SELECT bear, max(kg) AS kg FROM sightings GROUP BY bear ORDER BY bear", db)
  db_sqlite.close(db)

nbText: """
## 8. Testing helpers

`polars.testing` has `assert_frame_equal` and `assert_series_equal`, used by every test
suite that touches Polars. Nanuq's `nanuq/testing` has the same four procs in camelCase,
with Python's options (`checkRowOrder`, `checkColumnOrder`, `checkDtypes`, `checkExact`,
`rtol`, `atol`). On failure they raise `AssertionDefect` (what Nim's `doAssert` raises)
with the first difference, so `unittest` shows which column and row.
"""

nbCode:
  import nanuq/testing
  try:
    assertFrameEqual(sightings.head(2), sightings.tail(2))
  except AssertionDefect as e:
    echo e.msg

nbText: """
## 9. Smaller functions, and comparisons that keep their names

The rest came from the book map, which lists the Polars functions each blocked book
section needs. The method spellings of operators (`a.mul(2)`, `a.sub(b)`) exist because
the books chain them; `xor`, `joinWhere` (joins on inequalities), `intRanges`,
`unstack`, `hist`, `rollingMap` (with a typed Nim proc over each window), `dtypeOf`
and a dozen others unblock a section or two each. Frames got the aggregations Python
has on frames (`df.mean`, `df.nullCount`), group-bys got the shortcuts (`g.sum`,
`g.head(2)`), and `for key, part in df.groupBy("bear")` iterates over the groups.

One fix is worth a paragraph. Nim has no reflected operators like Python's `__gt__` and
`__lt__`, so `0 < col("kg")` called the overload with the literal on the left, and the
result column was named `literal`. Worse, `all() > 0` (a selector) went through Nim's
`>` template, which rewrites it to `0 < all()`, so every column came out as `literal`.
Now comparisons with a value on the left are mirrored (`0 < x` is `x > 0`), as Python's
reflected comparisons do, and all operators take selectors directly. Arithmetic is not
mirrored (`1 + col("kg")` is named `literal`), which is also what Python does.
"""

nbCode:
  echo sightings.select((col(float, int) > 2).name.suffix(" > 2")).head(2)
  for key, part in sightings.groupBy("bear"):
    echo key[0], ": ", part.height, " rows"

nbText: """
## What did not make it

- **A formula macro.** Datamancer writes `f{"kg" * 2}`, and the plan proposed something
  similar. We dropped it: Polars expressions are already expressive, and if Nanuq gets
  Nim sugar for expressions it should be its own design, from cases where the method
  chains read badly. It is in the backlog as a design question.
- **Plotting.** The book's plotting sections use `df.plot`, which in Python is hvPlot
  or Altair. Nim's options are nim-plotly (used by the El Niño explainer) and ggplotnim
  (through `toDatamancer`); both work today with a line of conversion. A `plot`
  namespace waits until we know which one to wrap.
- **Cloud storage and a shared library.** Reading from S3 and shipping Nanuq as a
  dynamic library are about distribution, the theme of 0.7.
"""

nbSave
