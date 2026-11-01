import nimib
import std/os
import nanuq, nanuq/datasets
import ../nanuqtheme

nbInit
nb.title = "Designing Nanuq 0.2"
# dated slug for the dev log (module names can't start with a digit)
nb.doc.filename = nb.doc.filename.parentDir / "2026-10-31-designing-0-2.html"
nb.useNanuqTheme(
  titleHtml = "Designing Nanuq <em>0.2</em>",
  eyebrow = "Nanuq dev log · 31 October 2026",
  epigraph = "Looking back at the API choices behind 0.2: what Polars does, what Nim allows, and what we picked.",
  meta = "API design · Nanuq 0.2 · Polars 0.55 · Nim " & NimVersion & " · rendered with nimib",
  summary = "A look back at the API decisions of Nanuq 0.2: enums, casts, when/then, selectors, CSV options, fillNull and sample.",
)

nbText: """
Nanuq 0.2 shipped today with data types and casts, joins, frame verbs, conditional and
window expressions, column selectors and CSV options. The
[census post](2026-10-31-bear-census.html) shows what they do. This post covers how
their API was chosen. We wrote the explainer first, against the planned API, and every
place where the story needed a feature became a question: what does Polars do, what
does Nim allow, and which spelling reads best?

Unlike the [0.3 design post](2026-10-31-designing-0-3.html), everything here is
implemented, so the code runs. It uses the penguins dataset.
"""

nbCode:
  let df = penguins()

nbText: """
## Two conventions that shaped everything else

**Closed option sets are pure enums with Polars' names.** Python Polars passes options
as strings (`how="left"`), and Rust uses enums (`JoinType::Left`). Strings would be the
smallest wrapper, but Nim can check enums at compile time. So every closed set is a
`{.pure.}` enum with Rust's type and variant names: `JoinType.Left`,
`QuoteStyle.Necessary`, `FillNullStrategy.Forward`. Because the parameter is typed, the
bare `how = Left` works. Where Rust has no enum, the name comes from Python's strings in
PascalCase (`ConcatMethod.Diagonal`). This is now the `api-conventions` spec.

**Cast targets are Nim types.** `cast(int32)` rather than `cast(Int32)`. The
`DataType` constants (`Int64`, `String`) still exist with Polars' names, for schemas
and `schemaOverrides`. A small decision followed from it: dtype display names stay
Polars' (`i64`, `str`), because Polars renders `$df` in Rust and rewriting the table
renderer for Nim names wasn't worth it. `cast` is a Nim keyword, but keywords are fine
after a dot, so only a prefix call would need backticks.
"""

nbCode:
  nbShow df.select(col("year").cast(int16), col("body_mass_g").cast(float32)).head(3)

nbText: """
## when/then/otherwise

Polars starts a conditional with a free function called `when`, which is a Nim keyword.
After a dot the keyword is fine, so only the first call is a problem. These are the five
options we tested:

| Option | Example | Verdict |
|---|---|---|
| **A. Polars chain, backticked first call** | `` `when`(c).then("small").otherwise("big") `` | **Picked**, as the reference API |
| B. Rename the first call | `When(c)`, `whenever(c)` | A capitalised proc reads like a type, and other names are guesswork |
| C. `then` on the condition | `(c).then("small")` | The first `when` disappears and the chain reads unevenly |
| **D. A macro over Nim's `if`** | `choose: if c: "small" else: "big"` | **Picked**, as the spelling the docs use |
| E. A table of branches | `cases({c: "small"}, otherwise = "big")` | Every value must share one Nim type |

A and D coexist: `choose` rewrites each branch into the chain from A, so the plan is
the same. One deliberate difference from Python: a bare string in `then` or `otherwise`
is a *literal*, not a column name. In Python, `.then("small")` refers to a column
called "small", a well-known gotcha.
"""

nbCode:
  let size = choose:
    if col("body_mass_g") < 3500: "small"
    elif col("body_mass_g") < 4500: "medium"
    else: "large"
  nbShow df.select(col("species"), col("body_mass_g"), size.alias("size")).head(4)

nbText: """
Look at the fourth penguin. Its mass is null, so both conditions are null and the row
falls through to `else`: an unweighed penguin counts as "large". That is Polars'
behaviour, and it reads the same in Python. Check `isNull` first when nulls matter.

## Column selectors

Rust Polars has a `Selector` type, and Python a `polars.selectors` module
(`cs.numeric()`). Nim already has typeclasses for numbers, so we used them. We extended
the 0.2 idea that Nim types stand for dtypes:

- `col(SomeNumber)`, `col(SomeInteger)`, `col(SomeFloat)` select Polars' dtype
  categories;
- `col(float, int)` selects exact dtypes, and `col("a", "b")` selects by name;
- `all()` and `.exclude(...)` work on any selector, and a regex works through
  `col("^...$")`, as in Polars.

A `cs` constant with methods (`cs.numeric`) would have compiled, but it would be one
more namespace to learn. Bare `numeric()` and `float()` were ruled out, because a proc
named `float` hides the type conversion and `float(3)` stops compiling. Set operators
(`|`, `&`, `-`) are left out because `col("a") - col("b")` is already subtraction.

Writing the story exposed a gap: two aggregations over the same selector give
duplicate names. So `name.suffix` and `name.prefix` joined the change:
"""

nbCode:
  nbShow df.groupBy(col("species"))
    .agg(col(SomeFloat).mean.name.suffix("_mean"), col(SomeFloat).max.name.suffix("_max"))
    .sort("species")

nbText: """
## CSV options

Rust configures CSV reading with a builder (`CsvReadOptions::default().with_...`).
Python flattens the options into keyword arguments. We weighed four options: named
arguments, an options object, a builder like Rust's, and both of the first two. Named
arguments won: Nim's default parameters fit them naturally, and the call reads like
Python. A template generates the shared signature of `readCsv` and `scanCsv`.

A few details:

- `schemaOverrides` takes `DataType` values (`{"bears": Int64}`), because a Nim type
  can't be stored in a runtime table without a macro.
- `separator` is a `char`, because Rust takes a single byte.
- Optional ints are typed `int | Option[int]` rather than written as overloads.
- `readCsv` is `scanCsv(...).collect`, so the two can't drift apart.
"""

nbCodeSkip:
  let season = scanCsv("logs/*.csv",
    nullValues = ["lots", "many", "?"],
    schemaOverrides = {"bears": Int64, "collared": Boolean})
  report.writeCsv("governor.csv", separator = ';', decimalComma = true)

nbText: """
## fillNull strategies

Rust's `FillNullStrategy` carries the limit inside two of its variants
(`Forward(limit)`). A pure enum can't carry data, so `limit` became its own argument,
as in Python, and Python's `forwardFill` and `backwardFill` shortcuts came along. An
object variant that mirrors Rust exactly would have broken the bare `Forward` that the
enum convention gives. The strategy overload sits next to the existing
`fillNull(value)` without ambiguity.
"""

nbCode:
  nbShow df.select(
    col("sex"),
    col("sex").forwardFill.alias("forward"),
    col("body_mass_g").fillNull(Mean).alias("mass_or_mean"),
  ).slice(2, 3)

nbText: """
## A reproducible sample

Polars samples on the eager `DataFrame` only, and it is random unless a seed is given.
A fixed default seed would make rendered posts stable, but it would surprise anyone
who expects randomness. So we followed Polars and also wrapped its global seed. One call
to `setRandomSeed` at the top of a post or test makes every later random call
repeatable, the way `randomize(seed)` works in `std/random`. `n` and `fraction` are
separate overloads, so mixing them up fails at compile time.
"""

nbCode:
  setRandomSeed(42)
  nbShow df.sample(3).select(col("species", "island", "year"))

nbText: """
## Things we only learned by writing code

- `method` is a Nim keyword, and unlike `cast` it can't be a named argument. So
  `quantile` takes `interpolation = ...`, where Polars uses `method`.
- `drop` and `unique` take one name or a list. A Nim `varargs` followed by a named
  parameter can't take several positional values.
- `round` was missing from the plan until the census needed it.
- `toSeq(df, column, T)` clashes with `sequtils.toSeq`. That fix is in 0.3, which
  renames it to `toList`.

The process worked: an explainer first, written against the planned API, and then one
OpenSpec change per area. It gave every decision a concrete example to argue over. For
0.3 we did the same, starting with the
[0.3 design post](2026-10-31-designing-0-3.html).
"""

nbSave
