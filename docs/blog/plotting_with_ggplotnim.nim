import nimib
import std/os
import nanuq
import ggplotnim
import ../nanuqtheme

nbInit
nb.title = "Plotting a Nanuq DataFrame with ggplotnim"
# dated slug for the dev log (module names can't start with a digit)
nb.doc.filename = nb.doc.filename.parentDir / "2026-10-27-plotting-with-ggplotnim.html"
nb.useNanuqTheme(
  titleHtml = "Plotting with <em>ggplotnim</em>",
  eyebrow = "Nanuq dev log · 27 October 2026",
  epigraph = "Query in Polars, plot in Nim.",
  meta = "Polars 0.55 · ggplotnim · Nim " & NimVersion & " · rendered with nimib",
)
# nimib runs the code from the repository root

nbText: """
How do we plot a Nanuq DataFrame? The obvious candidate in Nim is
[ggplotnim](https://github.com/Vindaar/ggplotnim), a grammar of graphics library
modelled on R's ggplot2. This post shows what works today, with no new code in Nanuq,
and then looks at what a smoother bridge could be. It follows
[How Nanuq works](2026-10-27-how-nanuq-works.html).

## What ggplotnim takes as input

ggplotnim has a single entry point, `ggplot(data: DataFrame, aes)`, and the
`DataFrame` there is the one from [Datamancer](https://github.com/SciNim/Datamancer),
a pure Nim dataframe library that ggplotnim depends on. There is no input from plain
seqs. Datamancer, however, builds a DataFrame straight from seqs, and Nanuq gives
us seqs with `toSeq(df, column, T)`. That is the whole bridge for now.

## Importing both

Both libraries have a `DataFrame` and a `readCsv`, so with both imported Nim asks us
to pick. Qualifying the call as `nanuq.readCsv` is enough; everything else (`col`,
`filter`, `ggplot`, `aes`) resolves by type.

```nim
import nanuq
import ggplotnim
```
"""

nbCode:
  let iris = nanuq.readCsv("examples/iris_sample.csv")
  echo iris.shape

nbText: """
## From Nanuq to Datamancer

`toDf` takes a table constructor of column names and seqs. Each `toSeq` copies one
Polars column into a Nim seq.
"""

nbCode:
  let points = toDf({
    "sepal_length": iris.toSeq("sepal_length", float),
    "petal_length": iris.toSeq("petal_length", float),
    "species": iris.toSeq("species", string),
  })
  echo points.head(3)

nbText: """
## A scatter plot
"""

nbCode:
  ggplot(points, aes("sepal_length", "petal_length", color = "species")) +
    geom_point(size = 3.0) +
    ggtitle("Iris sample: petal vs sepal length") +
    ggsave("docs/blog/2026-10-27-iris-scatter.png", width = 640, height = 420)

nbRawHtml: """<figure><img src="2026-10-27-iris-scatter.png" alt="Scatter plot of petal length against sepal length, coloured by species"></figure>"""

nbText: """
## Aggregate in Polars, plot the result

Most plots don't need every row. The heavy work can stay in Polars, and only the
small result crosses over to Datamancer. Here Polars computes the mean petal length
per species, and three rows are converted.
"""

nbCode:
  let means = iris.lazy
    .groupBy(col("species"))
    .agg(col("petal_length").mean.alias("mean_petal_length"))
    .sort("species")
    .collect
  echo means

  let bars = toDf({
    "species": means.toSeq("species", string),
    "mean_petal_length": means.toSeq("mean_petal_length", float),
  })
  ggplot(bars, aes("species", "mean_petal_length", fill = "species")) +
    geom_bar(stat = "identity", position = "identity") +
    ggtitle("Mean petal length per species (computed by Polars)") +
    ggsave("docs/blog/2026-10-27-iris-means.png", width = 640, height = 420)

nbRawHtml: """<figure><img src="2026-10-27-iris-means.png" alt="Bar chart of mean petal length for setosa, versicolor and virginica"></figure>"""

nbText: """
## What this costs

The recipe works with no glue code, but it has two costs:

- **Copies.** Every column goes from Polars' Arrow buffers to a Nim seq, then into a
  Datamancer column. For a plot of a few thousand points this doesn't matter.
- **Reading cell by cell.** `toSeq` currently reads one cell per FFI call. Bulk column
  access is already in the backlog and would make this a single call per column.

And one inconvenience: we have to spell out the columns twice, once in `toDf` and once
in `aes`.

## Exploring: where this could go

This is the start of an exploration, not a plan. It is tracked in the
[backlog](https://github.com/pietroppeter/nanuq/blob/main/BACKLOG.md) under Ecosystem.
Three directions, from the smallest to the most ambitious:

1. **A small optional module, `nanuq/ggplot`.** An overload
   `ggplot(df: nanuq.DataFrame, aes(...))` that looks at the columns named in `aes`
   and converts only those. The core of Nanuq would not depend on Datamancer. This
   removes the double spelling and nothing else.
2. **Zero-copy columns.** Once columns cross through the Arrow C Data Interface,
   numeric Polars buffers could be wrapped without copying. Only worth it for very
   large plots.
3. **A Narwhals-style dataframe API.** Python's [Narwhals](https://narwhals-dev.github.io/narwhals/)
   lets libraries accept pandas, Polars and others through one Polars-like interface.
   A Nim equivalent would be a small common layer, implemented by both Nanuq and
   Datamancer, that ggplotnim (or any library) could accept directly. Datamancer is
   already generic over a `ColumnLike` concept, which is a promising hook.

Open questions for the exploration:

- Is a plotting bridge worth a module of its own, or should it wait for the
  Narwhals-style layer, which would make it unnecessary?
- Should the common layer be compile time (concepts and generics) or run time
  (a variant or ref type)?
- Which subset of operations does a library like ggplotnim actually need? Probably
  column names, column types and reading a column, which is much less than a full
  dataframe API.
"""

nbSave
