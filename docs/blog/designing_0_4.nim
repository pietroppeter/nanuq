import nimib
import std/os
import ../nanuqtheme

nbInit
nb.title = "Designing Nanuq 0.4"
# dated slug for the dev log (module names can't start with a digit)
nb.doc.filename = nb.doc.filename.parentDir / "2026-11-01-designing-0-4.html"
nb.useNanuqTheme(
  titleHtml = "Designing Nanuq <em>0.4</em>",
  eyebrow = "Nanuq dev log · 1 November 2026",
  epigraph = "Rolling windows, reshaping, a real Series and rows as objects: the API choices 0.4 had to make, and what we picked.",
  meta = "API design · runs on Nanuq 0.4 · rendered with nimib",
  summary = "The API decisions behind Nanuq 0.4: math, rolling windows, pivot, time windows, Series, row objects, Arraymancer, and what the explainer and the book ports changed.",
)

nbText: """
Nanuq 0.4 is the release the roadmap called "a real Series, and shaping". It adds about
two hundred functions, in ten planned OpenSpec changes: math, cumulative and rolling
functions, value functions (top k, recoding, binning), horizontal functions and
correlation, reshaping (pivot and friends), time windows and as-of joins, a Series you can
compute with, row objects, and Arraymancer tensors.

Then three more changes came from using it. Reviewing this post renamed a parameter.
Writing the 0.4 explainer in Python first, and porting the Nanuq Book chapters to 0.4,
turned up calls that Python users write all the time and Nanuq could not yet mirror.
Sections 9 to 11 are about those.

Most of it maps onto Polars without a question: `rollingMean`, `cumSum`, `topK`,
`unpivot` are Polars' names in camelCase. This post is about the places where Nim and
Polars disagree, and what we did there. Unlike the 0.3 post, which came before the code,
every snippet here runs, on a few made-up rows shaped like NOAA's El Niño index (the
subject of the 0.4 explainer).
"""

nbCode:
  import nanuq
  let oni = newDataFrame:
    season: ["1997 MJJ", "1997 JJA", "1997 JAS", "1997 ASO", "1997 SON",
             "1998 DJF", "1998 JJA", "1998 SON"]
    anomaly: [1.2, 1.5, 1.8, 2.1, 2.3, 2.2, -0.2, -1.1]

nbText: """
## 1. Math functions overload std/math

`sqrt`, `exp`, `floor`, `sin` and friends already exist in std/math for floats. Nanuq
defines them again for `Expr`, so both work in the same module and Nim picks by
argument type. Two Polars spellings needed a decision:

- **`clip` with one bound.** Python has `clip(lower_bound=None, upper_bound=None)`.
  In Nim, two overloads with one optional bound each would make `clip(0)` ambiguous. We
  kept it ambiguous on purpose: `clip(0)` doesn't compile, and you name the bound,
  `clip(lowerBound = 0)`. The two-bound form is positional.
- **NaN is not null.** Polars keeps the float NaN apart from a missing value, and so does
  Nanuq: `isNan`, `fillNan`, `dropNans` next to `isNull`, `fillNull`, `dropNulls`.
"""

nbCode:
  echo oni.select(col.anomaly.clip(-1.0, 2.0).alias("clipped"),
                  col.anomaly.clip(lowerBound = 0.0).alias("warm_only"),
                  col.anomaly.abs.sqrt.round(2).alias("sqrt_abs"))

nbText: """
## 2. Option values stay enums

The 0.2 rule holds: a closed set of options is a pure enum named after Rust Polars. So
`diff(nullBehavior = NullBehavior.Drop)`, `interpolate(how = InterpolationMethod.Nearest)`,
`searchSorted(x, SearchSortedSide.Left)`, `pivot(aggregateFunction = PivotAgg.Sum)`,
`joinAsof(strategy = AsofStrategy.Nearest)` and `groupByDynamic(label = Label.Right,
startBy = StartBy.Monday)`.

One new tool turned out to be the star of the release: `rleId`, which numbers runs of
equal consecutive values. An El Niño *event* is a run of at least five overlapping seasons
at +0.5 °C or more, so counting events is a group-by on the run id:
"""

nbCode:
  let runs = oni
    .withColumns((col.anomaly >= 0.5).alias("warm"))
    .withColumns(col.warm.rleId.alias("run"))
    .filter(col.warm)
    .groupBy(col.run)
    .agg(col.season.first.alias("from"), col.season.last.alias("to"),
         col.anomaly.max.alias("peak"), col.season.len.alias("seasons"))
    .filter(col.seasons >= 5)
  echo runs

nbText: """
## 3. Windows: rows or time

Polars has two families of rolling functions: `rolling_mean(window_size=3)` counts rows,
and `rolling_mean_by("date", window_size="3mo")` spans time. Nanuq keeps both, and the
time window takes a std/times interval as well as Polars' duration string, as 0.3's
`dateRange` does: `rollingMeanBy("day", 7.days)` or `rollingMeanBy("day", "7d")`.

The exponentially weighted functions take their decay as exactly one of `com`, `span`,
`halfLife` or `alpha`. Python uses None for "not given"; Nanuq uses NaN, so the
parameters stay plain floats and must be named: `ewmMean(span = 3)`. Rust takes only
alpha, so Nanuq converts the others the way Python does.
"""

nbCode:
  echo oni.select(col.season, col.anomaly.rollingMean(3).round(2).alias("3-season mean"),
                  col.anomaly.ewmMean(span = 3).round(2).alias("ewm"))

nbText: """
## 4. Recoding with Nim's mapping literal

Python's `replace` takes a dict. Nim has no dict literal, but it has the next best thing:
`{"a": "x", "b": "y"}` is an array of pairs, and that is what `replace` and
`replaceStrict` take. `cut` and `qcut` bin numbers into labels; like Python Polars 2,
the result is an Enum, so the bins sort in order.
"""

nbCode:
  echo oni.select(col.season,
                  col.anomaly.cut([-0.5, 0.5, 1.5], labels = ["La Niña", "neutral",
                                                             "El Niño", "strong El Niño"])
                    .alias("phase"))

nbText: """
## 5. Optional parameters of several types

This was the most interesting Nim problem of the release. Python's `pivot` takes
`index="year"` or `index=["year", "month"]`, and `join_asof` takes a tolerance that is a
duration string or a number. The natural Nim spelling is a union type,
`index: string | openArray[string] = []`, but Nim rejects it: a default value fixes the
generic type, so a call that passes the other type no longer matches.

Overloads for every combination would multiply quickly (pivot has three such
parameters). So 0.4 adds four small parameter types, each with converters from the types
it accepts:

| Type | Accepts | Used by |
|---|---|---|
| `ColumnNames` | a name, a seq or an array of names | `pivot`, `unpivot`, `partitionBy`, `toDummies`, `joinAsof`'s `by` |
| `OptInterval` | a std/times interval or a duration string | `groupByDynamic`'s `period` and `offset`, `rolling`'s `offset` |
| `JoinKey` | a column name or an expression | `joinAsof`'s `on`, `leftOn`, `rightOn` |
| `AsofTolerance` | an interval, a duration string, an int or a float | `joinAsof`'s `tolerance` |

The converters only apply where these types appear, so they don't leak into the rest of
the API, and the calls read like Python:
"""

nbCode:
  let wide = oni
    .withColumns(col.season.str.slice(0, 4).alias("year"),
                 col.season.str.slice(5).alias("months"))
    .pivot("months", index = "year", values = "anomaly")
  echo wide
  echo wide.unpivot(index = "year", variableName = "months", valueName = "anomaly")
    .dropNulls.sort(["year", "months"])

nbText: """
## 6. A Series that is a thin layer over expressions

A Series is a single named column with its values: `oni["anomaly"]` takes one out of a
frame. Until 0.3 Nanuq had Series only as a way to build frames. In 0.4 you can compute
with them, and the question was how to give them hundreds of methods without writing
hundreds of procs.

**Every Series method is an expression in disguise.** Python Polars already works this
way: most of its Series methods put the Series in a one-column frame, run the matching
expression on it, and take the column back out. Nanuq does the same, generated by a macro
from a list of expression method names. So these two lines are the same computation:

```nim
s.rollingMean(3)
s.toFrame.select(col(s.name).rollingMean(3)).toSeries   # what the macro writes
```

The advantage is that anything an expression can do, a Series can do too (rolling,
ranking, binning, math), and adding a method to `Expr` adds it to `Series` by adding one
name to the list. Methods that need a second column, like `filter(mask)` or `s1 + s2`,
are written by hand: they put both Series in one frame first.

Two choices differ from Python:

- **Aggregations return a Series of one value.** In Python, `s.max()` returns a plain
  float or int, decided at run time by the column's type. A Nim proc must declare its
  return type when it is compiled, and one `max` serves float and int columns alike. So
  `s.max` returns a Series holding one value, and you read it with the type you expect:
  `s.max.item(float)`. If the type is wrong you get an error, not a silent conversion.
- **A Series is not automatically an expression.** It would be handy to write `col.x +
  s`, so we tried an implicit converter from `Series` to `Expr`. But Nim's overload
  resolution then had two candidates for `s.rollingMean(3)`: the Series method, and the
  expression method reached through the converter. It picked the expression one, which
  returns an `Expr` instead of a Series. So there is no converter. To use a Series inside
  an expression you wrap it, `lit(s)`, and to add one to a frame there is
  `df.withColumns(s)`.

Here the Series is the anomaly column: its maximum and where it is, the values
standardized (minus the mean, divided by the standard deviation), and the values above 2.
"""

nbCode:
  let s = oni["anomaly"]
  echo s.max.item(float), " at row ", s.argMax.item(int)
  echo ((s - s.mean.item(float)) / s.std.item(float)).round(2).toList(float)
  echo s.filter(s > 2.0).toList(float)

nbText: """
### Putting a Series back into a frame: `lit`

`lit` is short for *literal*: a fixed value written into the query, as opposed to `col`,
which looks a column up by name when the query runs. You already know `lit(2.0)`, a
single number that Polars repeats on every row. `lit(s)` is the same idea for a whole
column of values: the Series goes into the query as it is, under its own name. It must
have one value per row of the frame it meets (or a single value, which is repeated).

Say we have a Series computed somewhere else, a reference anomaly for each of the eight
seasons, and we want each season's distance from it. `col.anomaly - reference` does not
compile, because `reference` is a Series and `-` with an expression wants another expression.
Wrapping it does:
"""

nbCode:
  let reference = series("reference", [1.0, 1.0, 1.5, 1.5, 2.0, 2.0, 0.0, -0.5])
  echo oni.select(
    col.season,
    col.anomaly,
    lit(reference),                                    # the Series as a column
    (col.anomaly - lit(reference)).alias("vs reference"),
  )

nbText: """
To add a Series as a new column there is no need for an expression at all:
`withColumns` takes Series directly, as Python's `with_columns` does.
"""

nbCode:
  echo oni.withColumns(reference, s.rank.alias("rank")).head(3)

nbText: """
## 7. Rows as Nim objects

Python returns rows as tuples or dicts. Nim has types, so you say which one you want:
`df.rows(T)` and `df.iterRows(T)` fill an object or named tuple whose fields name columns,
and `toDataFrame` goes the other way. Fields can be numbers, strings, booleans, dates,
Nim enums, or `Option` of these for columns with nulls. The implementation is plain
`fieldPairs`, one `toList` per field, so a row type costs nothing at run time beyond
reading the columns.
"""

nbCode:
  type Peak = object
    season: string
    anomaly: float
  for p in oni.filter(col.anomaly > 2.0).iterRows(Peak):
    echo p.season, ": +", p.anomaly, " °C"
  echo @[Peak(season: "2015 NDJ", anomaly: 2.6)].toDataFrame

nbText: """
## 8. Arraymancer lives in its own module

Like the Datamancer bridge, the Arraymancer bridge is an optional module, so the core
library doesn't depend on Arraymancer: `import nanuq/arraymancer` adds
`df.toTensor(float)` (a 2-D tensor, one row per row, like `to_numpy`), `toTensor` for a
column or Series, and `toSeries` and `toDataFrame` back. Nulls become NaN in float
tensors and raise in integer ones. It copies; zero-copy waits for the Arrow C Data
Interface. The bridge doesn't re-export Arraymancer, so to print, slice or compute with
the tensor you import Arraymancer itself, as here.

Making this example run (it was first left unrun) found a bug. `toDataFrame(tensor)`
took a tensor column with Arraymancer's slicing syntax, `t[_, j]`. That syntax is a
macro, and inside a generic proc it is resolved where the proc is *called*. So
`toDataFrame` compiled in the tests, which import Arraymancer, and failed for a user who
imported only `nanuq/arraymancer`. The bridge now copies with plain `t[i, j]` indexing.
"""

nbCode:
  import arraymancer, nanuq/arraymancer
  let t = oni.select(col.anomaly).toTensor(float)   # 8 rows x 1 column
  echo t.shape
  echo t
  echo t.toDataFrame(["anomaly"]).head(3)

nbText: """
## 9. `method` is a keyword, so it is `how`

Python Polars picks the variant of `rank`, `corr` and `interpolate` with a parameter
called `method`: `rank(method="dense")`, `pl.corr(a, b, method="spearman")`. In Nim,
`method` is a reserved word (it declares a dynamically dispatched proc), so no parameter
can have that name.

The first drafts of 0.4 worked around it three different ways: `rank(rankMethod = ...)`
(from 0.3), `corr(a, b, correlationMethod = ...)` and `interpolate(interpolation = ...)`.
Each was defensible alone, but together they were long and inconsistent, and you had to
remember which one each function used. We looked at four options:

| Option | Looks like | Verdict |
|---|---|---|
| A short common name | `corr(a, b, how = Spearman)` | chosen |
| Separate functions, as Rust Polars does | `spearmanRankCorr(a, b)` | long, and unfamiliar to Python users |
| Backticks | ``corr(a, b, `method` = Spearman)`` | Python's name, but ugly whenever you write it |
| `kind` | `corr(a, b, kind = Spearman)` | short, but vaguer |

`how` won because Polars already uses it for exactly this, "which variant": `join(how=
"left")` and `concat(how="vertical")`. Now there is one rule, written into the API
conventions: **where Python has `method`, Nanuq has `how`**. Where Python uses another
name, Nanuq keeps it (`quantile(interpolation = ...)`). Most calls pass the enum by
position anyway, so they don't change:
"""

nbCode:
  let scores = newDataFrame:
    year: [1982, 1997, 2015, 2023]
    oni: [2.2, 2.4, 2.6, 2.0]
    rain: [1400.0, 1700.0, 600.0, 450.0]
  echo scores.select(col.year,
                     col.oni.rank(how = Dense, descending = true).alias("oni_rank"),
                     col.rain.rank(Min, descending = true).alias("rain_rank"))
  echo scores.select(corr("oni", "rain").round(2).alias("pearson"),
                     corr("oni", "rain", how = Spearman).round(2).alias("spearman"))

nbText: """
## 10. An eager group-by returns a frame

In Python, `df.group_by("a").agg(...)` on a DataFrame returns a DataFrame, and on a
LazyFrame a LazyFrame. Until this release, Nanuq's eager `groupBy` was a shortcut for
`df.lazy.groupBy(...)`, so `agg` returned a LazyFrame and every eager group-by ended in
`.collect`. Porting the book chapters made the difference obvious: every eager group-by
needed one more call in Nim than in Python.

Now a DataFrame's `groupBy` (and `groupByDynamic` and `rolling`) returns a small
`GroupBy` type, whose `agg` runs the query and returns a DataFrame. A LazyFrame keeps
`LazyGroupBy`, whose `agg` stays lazy. `groupBy` also takes column names now, as in
Python:
"""

nbCode:
  let byPhase = oni
    .withColumns((col.anomaly >= 0.5).alias("warm"))
    .groupBy("warm")
    .agg(col.anomaly.mean.round(2).alias("mean"), col.season.len.alias("seasons"))
  echo byPhase    # a DataFrame: nothing to collect

nbText: """
The change broke every `.collect` after an eager group-by, and here Nim had a surprise.
Once a DataFrame has no `collect`, `df.groupBy(...).agg(...).collect` still compiles: Nim
finds std/sugar's `collect` macro (which builds a seq from a loop) and applies it. The
query then prints as `@[shape: ...]`, a seq holding one frame. No error, just wrong output.

So Nanuq defines `collect` for a DataFrame on purpose, as an error:

```nim
proc collect*(df: DataFrame): DataFrame {.error: "this is already a DataFrame " &
    "(eager groupBy(...).agg(...) returns one since 0.4): drop the .collect".}
```

A leftover `.collect` now fails at compile time with that message, pointing at the right
line. It found every leftover in our tests and older posts at once.

## 11. What the explainer and the book asked for

Writing the El Niño explainer in Python Polars first, and porting the book, gave us two
lists of calls that 0.4 could not mirror. Most were small. Each one got the Python
behaviour, with a Nim twist where Nim needed one. The events below are made up, shaped
like the strong El Niños since 1970.

**Whole-row top k.** The explainer's most used call was `df.top_k(5, by="peak")`, the five
strongest events as whole rows. 0.4 had `topK` only on expressions, which returns one
column. Frames now have `topK(k, by, reverse)` and `bottomK`, where `by` is a name, a list
of names, or expressions. Python doesn't promise an order for the result; Nanuq returns
the largest first, which is what Rust Polars does and what you want to print.

**`any` and `all`** are aggregations on boolean columns, with `ignoreNulls` as in Python.
The name `all` was already taken by the `all()` column selector; Nim overloads by
arguments, so `all()` stays the selector and `col.x.all` is the aggregation.

**`date` from parts.** `pl.date(year, month, 15)` builds a Date column from integer
columns. Nanuq already had `date(2026, 1, 15)`, which returns a Nim `Date` value. Now, if
any part is an expression, `date` returns an expression instead; with three numbers it
still gives a value. We did not add Python's `datetime(...)` constructor: Nim names are
style-insensitive, so `datetime` would be the same name as std/times' `dateTime`, and
the two would clash in ordinary code.

**`floatPrecision`.** Python's `pl.Config(float_precision=2)` keeps tables readable. It
joins the other display options in `setConfig` and `withConfig`.
"""

nbCode:
  let events = newDataFrame:
    year: [1972, 1982, 1997, 2015, 2023]
    month: [11, 12, 11, 11, 12]
    peak: [2.1, 2.2, 2.4, 2.6, 2.0]
    floods: [false, true, true, false, false]
  withConfig(floatPrecision = 1):
    echo events.topK(3, by = "peak")
      .withColumns(date(col.year, col.month, 15).alias("peak_month"),
                   (col.peak / 3.0).alias("third"))
  echo events.select(col.floods.any.alias("any_floods"), col.floods.all.alias("all_floods"))

nbText: """
**`nil` as Python's `None`.** Python writes `fill_nan(None)` to turn NaN into missing
values. Nim's closest word is `nil`, and a proc can take a parameter of type
`typeof(nil)`, so `lit(nil)` is a null literal and `fillNan(nil)` works as in Python.
`gatherEvery(n, offset)` also works on frames now, keeping every n-th row.
"""

nbCode:
  let raw = newDataFrame:
    month: [1, 2, 3, 4, 5, 6]
    sst: [26.1, NaN, 26.8, 27.4, NaN, 28.0]
  echo raw.withColumns(col.sst.fillNan(nil)).gatherEvery(2)

nbText: """
The longer items from the book's list (`over` with a mapping strategy, `shuffle`, `hash`,
`extendConstant`, `partitionBy` as a dict, printing dtypes as Python does) are in the
backlog.

## Small things

- `repeat(lit("x"), 3)`: with a plain string, std/strutils' `repeat` wins the overload, so
  strings go through `lit`.
- `Expr.head` and `tail` default to 10 values, as in Python; frames keep 5.
- `pivot` with `PivotAgg.Sum` gives 0 for empty cells, as Python does.

## What's next

0.5 is about nested data: List, Array and Struct columns (`explode`, `unnest`,
`str.split`, `Expr.valueCounts`), JSON, and calling Nim from Polars (`mapElements`).
And the 0.4 explainer, "Counting El Niños", is on its way.
"""

nbSave
