import nimib
import std/os
import ../nanuqtheme

nbInit
nb.title = "Designing Nanuq 0.5"
# dated slug for the dev log (module names can't start with a digit)
nb.doc.filename = nb.doc.filename.parentDir / "2026-11-01-designing-0-5.html"
nb.useNanuqTheme(
  titleHtml = "Designing Nanuq <em>0.5</em>",
  eyebrow = "Nanuq dev log · 1 November 2026",
  epigraph = "Lists, structs, JSON, SQL and Nim procs that Polars calls back: the API choices 0.5 had to make, and what we picked.",
  meta = "API design · runs on Nanuq 0.5 · rendered with nimib",
  summary = "The API decisions behind Nanuq 0.5: nested data types, the list, struct and arr namespaces, JSON, SQL, Nim callbacks, and the smaller functions the book asked for.",
)

nbText: """
Nanuq 0.5 is the release the roadmap called "nested data and user code". Until now a
Nanuq column held one number, string, date or category per row. Now a cell can hold a
list, a fixed-size array or a struct, and Polars can call your Nim procs. That unblocks
most of what the Nanuq Book still marked "not yet": `explode`, `str.split`,
`struct.field`, `list.eval`, `valueCounts`, `unnest`, `readJson`, `mapElements`, SQL.

It came in eight OpenSpec changes: nested data types, the list namespace, string
functions that return lists, structs and arrays, JSON, SQL, Nim callbacks, and a bag
of smaller functions. As before, most names are Polars' names in camelCase. This post is
about the places where Nim and Polars disagree. Every snippet runs, on a few made-up rows
about Alpine peaks above 4000 m (the subject of the 0.5 explainer).
"""

nbCode:
  import std/[options, strutils, streams]
  import nanuq
  let peaks = newDataFrame:
    peak: ["Mont Blanc", "Monte Rosa", "Gran Paradiso", "Weisshorn"]
    m: [4806, 4634, 4061, 4506]
    countries: [@["France", "Italy"], @["Italy", "Switzerland"], @["Italy"], @["Switzerland"]]
    huts: [@["Goûter", "Cosmiques"], @["Margherita"], @["Vittorio Emanuele", "Chabod"], @[]]
  echo peaks

nbText: """
## 1. Nim types are Polars types, recursively

0.2 settled that `cast(float)` and `schema["m"] == Int64` use Nim types where Nim has
them. 0.5 extends that to nested types:

| Polars | Nanuq data type | Nim value |
|---|---|---|
| `pl.List(pl.String)` | `List(String)` | `seq[string]` |
| `pl.Array(pl.Float64, 3)` | `Array(Float64, 3)` | `array[3, float]` |
| `pl.Struct({"x": pl.Int64})` | `Struct({"x": Int64})` | an object or a named tuple |

So `dataType(seq[seq[int]]) == List(List(Int64))`, and an object type maps to a Struct
with one field per Nim field. `DataType` became a recursive variant object. Nim can't
put a type inside itself directly, so the inner type lives in a one-element `seq`, and
`dt.inner` hides that. `Array(Int64, [2, 3])` is the same type as
`Array(Array(Int64, 3), 2)`, as in Polars, and `shape` gives `@[2, 3]` back.

Printing follows Python Polars: `list[str]`, `array[f64, 3]`, `struct[2]`.
"""

nbCode:
  echo peaks.schema
  echo dataType(seq[seq[int]]), "  ", Array(Float64, [2, 3]), "  ",
       Struct({"lat": Float64, "lon": Float64})

nbText: """
## 2. Building and reading nested columns

You build nested columns with plain Nim values, in `newDataFrame`, `series` or `lit`.
There were three small choices:

- **Empty lists.** `@[]` has no element type in Nim. In a `newDataFrame` block it takes
  the type of the other rows, as `nil` does for missing values since 0.3. The `huts`
  column above has an empty list in its last row.
- **Tuples and objects become structs.** A named tuple or an object value gives a Struct
  column. Python uses dicts, which in Nim would lose the field types.
- **`array[N, T]` becomes an Array**, so the width is known at compile time.

To read them back you name the Nim type, as for any column: `toList("huts", seq[string])`.
A list with nulls inside needs `seq[Option[string]]`. A null list needs
`Option[seq[string]]`. If you ask for the plain type and there are nulls,
`toList` raises `InvalidOperationError`.
"""

nbCode:
  type Summit = object
    lat: float
    lon: float
  let summits = newDataFrame:
    peak: ["Mont Blanc", "Weisshorn"]
    at: [Summit(lat: 45.83, lon: 6.86), Summit(lat: 46.10, lon: 7.72)]
    rgb: [[255, 255, 255], [200, 210, 230]]
  echo summits
  echo peaks.toList("huts", seq[string])
  echo summits.toList("at", Summit)

nbText: """
## 3. `element()` and the list namespace

The list namespace, `col("huts").list`, is about fifty functions with Polars' names:
`len`, `first`, `get`, `contains`, `join`, `sort`, set operations and so on. The
interesting part is `list.eval`, which runs an expression on the elements of each list.
Python spells the element `pl.element()`, and so does Nanuq: `element()` is just a
column with an empty name. `list.agg` is `list.eval` that must return one value per list.
"""

nbCode:
  echo peaks.select(
    col.peak,
    col.huts.list.len.alias("n_huts"),
    col.huts.list.first.alias("first_hut"),
    col.countries.list.contains("Italy").alias("in_italy"),
    col.countries.list.join(" / ").alias("border"),
    col.huts.list.eval(element().str.lenChars).alias("hut_name_lengths"))

nbText: """
`explode` and `implode` go between lists and rows. On frames, `explode` takes column
names, and an empty list gives a row with a null (Python's default; pass
`emptyAsNull = false` to drop the row instead).
"""

nbCode:
  echo peaks.explode("countries").groupBy("countries")
    .agg(col.peak.alias("peaks"), col.m.max.alias("highest"))
    .sort("countries")

nbText: """
## 4. `asStruct`, because `.struct` is taken

Python has a function `pl.struct(...)` that builds a struct and a namespace
`col("x").struct` that reads one. Nim can't have both: in Nim, `col("x").struct` and
`struct(col("x"))` are the same call. The namespace is used far more often, so it keeps
the name, and the constructor is `asStruct`, its Rust name (`as_struct`).

`Expr.valueCounts` returns a struct column, as in Polars, and `unnest` turns its fields
into columns. On frames, `unnest(separator = "_")` prefixes the field names, which is a
Polars 1.x option.
"""

nbCode:
  let s = peaks.select(asStruct(col.peak, col.m).alias("summit"))
  echo s.select(col.summit.struct.field("m"), col.summit.struct.jsonEncode.alias("json"))
  echo peaks.explode("countries").select(col.countries.valueCounts(sort = true))
    .unnest("countries")

nbText: """
## 5. String functions that return lists

0.3 left out `str.split`, `extractAll` and `extractGroups`, because they return lists and
structs. They are in now, with `splitExact` and `splitn` giving structs, as in Polars.
`replaceMany` takes a Nim table literal, `{"a": "x"}`, like `replace` does since 0.4.
`jsonDecode` takes either a `DataType` or a Nim type: `jsonDecode(Summit)`.
"""

nbCode:
  let routes = newDataFrame:
    route: ["Goûter: 2 days, PD", "Hörnli: 2 days, AD", "Normal: 1 day, F"]
  echo routes.select(
    col.route.str.split(": ").list.first.alias("name"),
    col.route.str.extractGroups(r"(?<days>\d) days?, (?<grade>\w+)").alias("parts"))
    .unnest("parts")

nbText: """
## 6. JSON and NDJSON

`readJson`, `readNdjson`, `scanNdjson`, `writeJson` and `writeNdjson` take a path or a
Nim `Stream`, like the CSV and Parquet functions. `toJson` and `toNdjson` return the
text. Python's `write_json()` with no path also returns a string; in Nim a proc that
sometimes writes and sometimes returns is awkward, so they are two names.

`inferSchemaLength = none(int)` reads every row to infer the schema, which matters for
NDJSON with structs whose fields differ between rows.
"""

nbCode:
  let text = summits.select(col.peak, col.at).toNdjson
  echo text
  echo readNdjson(newStringStream(text)).unnest("at")

nbText: """
## 7. SQL, with tables by variable name

`SQLContext` mirrors Python: `register`, `unregister`, `tables`, `execute`. Python's
`execute(query, eager=True)` returns a DataFrame and `eager=False` a LazyFrame. Nim procs
have one return type, so here `eager` is a `static bool`: the compiler knows it and
picks the return type. `execute(q)` alone gives a LazyFrame.

Python can also build a context from local variables, `pl.SQLContext(frames=locals())`.
Nim has no `locals()`, but it has macros: `sqlContext(peaks, routes)` registers each frame
under its variable name.
"""

nbCode:
  let ctx = sqlContext(peaks)
  echo ctx.execute("""
    SELECT peak, m FROM peaks WHERE m > 4500 ORDER BY m DESC""", eager = true)
  echo peaks.sql("SELECT COUNT(*) AS n, MAX(m) AS top FROM self")

nbText: """
## 8. Nim procs that Polars calls

`mapElements` runs a Nim proc on each value. In Python the return type is guessed from
the first results, or given with `return_dtype`. In Nim the proc's type says it all:
`proc (x: int): string` reads Int64 and gives a String column. A proc that takes an
object or a tuple gets each struct row as that type, and one that returns a `seq` gives a
List column. Nulls are skipped, unless the proc takes an `Option`, as in Python's
`skip_nulls=True` default.

`mapBatches` gets whole Series, and in a group-by it gets one group at a time, so it
can aggregate (`returnsScalar = true` tells Polars it does). `fold`, `reduce`, `cumFold`,
`name.map` and `GroupBy.mapGroups` work the same way.

Polars runs expressions on its own threads. The callbacks go through a lock, so only
one Nim proc runs at a time, and Nim's memory management needs no setup. A Nim exception
in a callback becomes a Polars `ComputeError` with the same message. It never crosses the
C ABI as a Nim exception.
"""

nbCode:
  type Peak = object
    peak: string
    m: int
  let feetPerMetre = 3.28084
  echo peaks.select(
    col.m.mapElements(proc (x: int): int = int(x.float * feetPerMetre)).alias("feet"),
    asStruct(col.peak, col.m).mapElements(proc (p: Peak): string =
      p.peak.split(' ')[^1] & " " & $p.m).alias("label"),
    col.huts.mapElements(proc (h: seq[string]): bool = h.len > 1).alias("several_huts"))
  echo peaks.select(fold(lit(0), proc (acc, x: Series): Series = acc + x,
                         col.m, col.m).alias("twice"))

nbText: """
## 9. Smaller functions

The 0.4 book ports left a list of Polars functions that Python users reach for, and 0.5
adds them: `over(mappingStrategy = MappingStrategy.Explode)`, `shuffle`, `sample`,
`hash`, `get`, `argTrue`, `upperBound` and `lowerBound`, `extendConstant`, `rle`,
`reshape`, `name.toLowercase`, a `meta` namespace (`outputName`, `rootNames`),
`equals`, `vstack`, `hstack`, `extend`, `update`, `upsample`, `estimatedSize` and
`collectAll`.

Two of them needed a choice:

- **`partitionBy(asDict = true)`** gives a Python dict keyed by tuples. A Nim table needs
  one key type, so the keys are `seq[string]` with each value as text; a typed table
  would need the key types at compile time.
- **`hash(seed)`** takes one seed. Python takes four, but only the first matters for
  most uses, and Rust Polars takes one.

One more fix came with `fold`: an operation between a Series of length 1 and a longer
one now broadcasts, as it does in Polars.
"""

nbCode:
  echo peaks.estimatedSize(SizeUnit.Kilobytes), " kB"
  let e = (col.m * 2).alias("double")
  echo e.meta.outputName, " from ", e.meta.rootNames
  let parts = peaks.explode("countries").partitionBy("countries", asDict = true)
  for key, part in parts:
    echo key, ": ", part.height, " rows"

nbText: """
## What's next

0.6 is the "production" release: streaming sinks, cloud storage, Arrow interop,
decimals and binary columns. And the 0.5 explainer, "Above 4000", is on its way.
"""

nbSave
