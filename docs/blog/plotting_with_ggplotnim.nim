import nimib
import std/os
import nanuq, nanuq/[datasets, datamancer]
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
  summary = "Plotting a Nanuq DataFrame with ggplotnim, and where a smoother bridge could go.",
)
# nimib runs the code from docs/ (see nimib.toml), so paths below are site paths

nbText: """
How do we plot a Nanuq DataFrame? The obvious candidate in Nim is
[ggplotnim](https://github.com/Vindaar/ggplotnim), a grammar of graphics library
modelled on R's ggplot2. This post shows how to hand a Nanuq DataFrame to it, and
then looks at where a smoother bridge could go. It follows
[How Nanuq works](2026-10-27-how-nanuq-works.html).

## What ggplotnim takes as input

ggplotnim has a single entry point, `ggplot(data: DataFrame, aes)`, and the
`DataFrame` there is the one from [Datamancer](https://github.com/SciNim/Datamancer),
a pure Nim dataframe library that ggplotnim depends on. So the bridge is a conversion:
the optional module `nanuq/datamancer` has `toDatamancer` and `fromDatamancer`, in the
spirit of Python Polars' `to_pandas` and `from_pandas`. Nanuq itself doesn't depend on
Datamancer; only that module does.

## Importing both

Both libraries have a `DataFrame` and a `readCsv`, so with both imported Nim asks us
to pick when we call `readCsv`: qualifying it as `nanuq.readCsv` is enough. Everything
else (`col`, `filter`, `ggplot`, `aes`) resolves by type. Here we don't even need
`readCsv`, since we use the Palmer penguins data bundled in `nanuq/datasets`.

```nim
import nanuq, nanuq/[datasets, datamancer]
import ggplotnim
```
"""

nbCode:
  let penguins = penguins()
  echo penguins.shape

nbText: """
## From Nanuq to Datamancer

`toDatamancer` copies every column, keeping names, order and types: integers become
`int` columns, floats `float`, strings `string`. Underneath it is one `toSeq` per
column, each a single call across the C ABI.

Two penguins have no measurements. A column with nulls would arrive as a Datamancer
object column with `null` entries, which ggplotnim plots less happily than a typed
column, so we drop those rows in Polars first.
"""

nbCode:
  let points = penguins.dropNulls("flipper_length_mm", "body_mass_g").toDatamancer
  echo points.head(3)

nbText: """
## A scatter plot
"""

nbCode:
  ggplot(points, aes("flipper_length_mm", "body_mass_g", color = "species")) +
    geom_point(size = 2.0) +
    ggtitle("Palmer penguins: body mass vs flipper length") +
    ggsave("blog/2026-10-27-penguins-scatter.png", width = 640, height = 420)

nbImage("blog/2026-10-27-penguins-scatter.png",
  caption = "Body mass against flipper length, coloured by species.",
  alt = "Scatter plot of body mass against flipper length, coloured by species")

nbText: """
## Aggregate in Polars, plot the result

Most plots don't need every row. The heavy work can stay in Polars, and only the
small result crosses over to Datamancer. Here Polars computes the mean body mass per
species (the mean skips nulls), and three rows are converted.
"""

nbCode:
  let means = penguins.lazy
    .groupBy(col("species"))
    .agg(col("body_mass_g").mean.alias("mean_body_mass_g"))
    .sort("species")
    .collect
  echo means

  ggplot(means.toDatamancer, aes("species", "mean_body_mass_g", fill = "species")) +
    geom_bar(stat = "identity", position = "identity") +
    ggtitle("Mean body mass per species (computed by Polars)") +
    ggsave("blog/2026-10-27-penguins-means.png", width = 640, height = 420)

nbImage("blog/2026-10-27-penguins-means.png",
  caption = "Mean body mass per species, aggregated by Polars before plotting.",
  alt = "Bar chart of mean body mass for Adelie, Chinstrap and Gentoo")

nbText: """
## What this costs

The conversion copies: every column goes from Polars' Arrow buffers to a Nim seq, then
into a Datamancer column. For a plot of a few thousand points this doesn't matter, and
for bigger data the second example is the pattern to follow: aggregate in Polars,
convert the small result.

## Exploring: where this could go

This is the start of an exploration, not a plan. It is tracked in the
[backlog](https://github.com/pietroppeter/nanuq/blob/main/BACKLOG.md) under Ecosystem.
Three directions, from the smallest to the most ambitious:

1. **A `ggplot` overload for Nanuq DataFrames.** `ggplot(df: nanuq.DataFrame, aes(...))`
   could convert only the columns named in `aes`, saving the explicit `toDatamancer`
   and the copies of unused columns.
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
