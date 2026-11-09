import nimib
import std/[strutils, math, options]
import nanuq
import ../nanuqtheme

nbInit
nb.useDevlogPost("what-about-arrow",
  epigraph = "Other wrappers pass data around as Apache Arrow, without copying it. Does Nanuq? Mostly it doesn't need to, and the rest of the answer is a map of where Nim's data libraries could go.")

nbText: """
A question came up on the [Nim forum](https://forum.nim-lang.org/t/14258) after
Nanuq was announced: *like other wrappers, does it use Apache Arrow (or similar) to
pass data without copying?* The short answer is yes where it matters, and that most
data never has to be passed at all. The long answer needs a few steps: what Arrow is,
why so much of the data world speaks it, how Polars uses it, what Nanuq does with it
today, and what a proper Arrow library would change, for Nanuq and for Nim's data
libraries more widely. This post takes them in that order.

## What Arrow is

[Apache Arrow](https://arrow.apache.org/) is first of all a **specification**: a
description, down to the byte, of how a table sits in memory. A table is a set of
columns. A column is a few contiguous buffers:

- a **validity bitmap**, one bit per value, set when the value is there (it can be
  left out when nothing is missing);
- the **values**, back to back: eight bytes per `Int64`, one bit per `Boolean`;
- for variable-length data (strings, lists) an **offsets** buffer saying where each
  value starts, or, in the newer *view* layout, a 16-byte view per value.

Because the layout is fixed, any program that knows it can read a column written by any
other program, in the same process, by being handed a pointer. That is the whole trick
behind "zero-copy": nobody converts anything, because everybody already agrees on the
format. Nanuq can show the buffers of a small column directly:
"""

nbCode:
  let kg = series("kg", [some(410), none(int), some(455)])
  var ex = kg.toArrow
  echo "format ", ex.schema.format, ", length ", ex.array.length,
       ", nulls ", ex.array.nullCount, ", buffers ", ex.array.nBuffers
  let validity = cast[ptr uint8](ex.array.buffers[0])[]
  echo "validity bits (last value first): ", validity.int.toBin(3)
  let values = cast[ptr UncheckedArray[int64]](ex.array.buffers[1])
  echo "values: ", values[0], ", (unused), ", values[2]

nbText: """
`l` is Arrow's format code for `Int64`. The bitmap reads `101`: the second value is
missing, and its slot in the values buffer is there but means nothing.

Around the format, the Arrow project grew a family of standards and libraries:

| Piece | What it is |
| --- | --- |
| Columnar format | The memory layout above |
| C Data Interface | Two C structs (`ArrowSchema`, `ArrowArray`) for handing columns between libraries in one process, and a third (`ArrowArrayStream`) for a stream of batches |
| IPC / Feather | The same layout written to a file or a socket, so reading it back is mostly a memory map |
| Flight, ADBC | Arrow over the network, and a database API that returns Arrow |
| Implementations | Libraries in C++, Rust, Go, Java, JavaScript, C (nanoarrow) and more, with readers, writers and compute functions |

The **C Data Interface** is the part that matters most for bindings. It is tiny (the
structs fit on one screen, and Nanuq's are in `src/nanuq/ffi.nim`), it needs no Arrow
library at all, and it is stable: the structs have not changed since they were
introduced in 2020. Python later added a thin layer on top, the
[PyCapsule interface](https://arrow.apache.org/docs/format/CDataInterface/PyCapsuleInterface.html)
(`__arrow_c_stream__` and friends), so Python libraries can swap tables without
depending on PyArrow.

## Who speaks Arrow

Most of the modern data stack, which is why "uses Arrow" is a fair thing to ask of a
new dataframe library:

- **DuckDB** scans Arrow tables in place and returns results as Arrow.
- **pandas** 2 can store columns in Arrow (`ArrowDtype`), and its string columns are
  moving to Arrow too.
- **DataFusion** (the Rust query engine) is built directly on arrow-rs.
- **Spark** uses Arrow to move data to and from Python (`toPandas`, pandas UDFs).
- **R** has the `arrow` package, and database drivers (ADBC, many cloud warehouses)
  hand results back as Arrow batches.
- Small libraries such as Narwhals or Altair accept any table that exposes
  `__arrow_c_stream__`, without knowing which library made it.

The pattern is the same everywhere. Each engine keeps its own compute, and Arrow is the
**common memory format at the borders**, so a table can go from a database to a
dataframe to a plot without being serialised.

## Arrow inside Polars

Polars goes further than most: Arrow is not only its border format but its memory.
Every Polars `Series` is a list of chunks, and every chunk is an Arrow array. Polars
started on the arrow2 crate and later folded it into its own crate, `polars-arrow`
(Nanuq's Rust side depends on it for exactly the C Data Interface). It does not use the
Arrow C++ or arrow-rs compute functions: the kernels, the query optimiser and the
streaming engine are Polars' own.

Polars also follows the newest parts of the format. Its strings are stored in the
**view** layout (`Utf8View`): a 16-byte view per value that holds short strings
inline and points into shared buffers for longer ones. That's what Nanuq exports too:
"""

nbCode:
  var peaks = series("peak", ["Dom", "Monte Rosa, Dufourspitze"]).toArrow
  echo "format ", peaks.schema.format, ", buffers ", peaks.array.nBuffers

nbText: """
`vu` is the format code of `Utf8View`. Libraries that only read the older
offsets layout need a conversion, which is what py-polars' `compat_level` argument is
for. Nanuq always exports the newest layout.

Two more places in Polars are pure Arrow C Data Interface: `to_arrow`/`from_arrow`
(how py-polars talks to PyArrow, pandas and DuckDB) and **expression plugins**, where
Polars hands each plugin a column as Arrow structs and takes the result back the same
way.

## Arrow in Nanuq today

A Nanuq `DataFrame` is a handle to a Polars frame on the Rust side. Expressions,
joins, group-bys, sorting, reading and writing files, and the streaming engine all run
inside Polars, on its Arrow buffers, and Nim only holds pointers. So the biggest
part of the answer to the forum question is that the data **doesn't cross** at all.

When it does cross, it depends on where it's going. Since 0.6, Nanuq has the C Data
Interface in both directions (`toArrow`/`fromArrow` for a Series, an
`ArrowArrayStream` for a frame) and **views**: a read-only look at a numeric column
without nulls, straight in Polars' memory.
"""

nbCode:
  let bears = newDataFrame:
    bear: ["Ada", "Bo", "Cy"]
    kg: [410.0, 380.5, 455.0]
  let v = bears.view("kg", float)
  echo v.len, " bears, ", sum(v.toOpenArray), " kg, heaviest ", max(v.toOpenArray)
  var stream = bears.toArrow             # an ArrowArrayStream, for any Arrow library
  echo fromArrow(stream).equals(bears)   # and back, without copying

nbText: """
Here is the full picture:

| Path | Copies? |
| --- | --- |
| Everything inside Polars (queries, IO, streaming) | No |
| `toArrow` / `fromArrow`, Series and frames | No (a Series made of several chunks is joined first) |
| `view` on a numeric column without nulls | No |
| `mapElements` with a Nim proc, numeric input without nulls | No on the way in, yes on the way out |
| `series(name, seq)`, `toList`, `toSeq` | Yes |
| Strings and nullable columns into Nim, UDF results | Yes |
| `toDatamancer`, `toTensor` (Arraymancer) | Yes |

How much a copy costs is easy to measure. Ten million `Float64` values, best of five
runs on a 4-core machine, from `benchmarks/arrow_views.nim`:

| Reading the column from Nim | Time |
| --- | --- |
| Polars computes the sum itself | 1.6 ms |
| `view`, then a Nim loop sums it | 8.3 ms |
| `toList` (a copy into a `seq`), then the same loop | 63 ms |
| Building the Series from a Nim `seq` (a copy in) | 61 ms |
| `mapElements(x * 2)`: view in, `seq` out | 91 ms |

A copy of 80 MB costs about 55 ms, seven times the loop that reads it. Polars' own
`sum` is faster still, which is the usual advice in Nim as in Python: stay in
expressions while you can. When Nim code does have to touch the values, a view makes
that cheap. The last row shows what's missing: results still go back as a `seq` that
Polars copies again.

One project uses the Arrow structs much more than Nanuq does:
[nanuq-more](https://github.com/pietroppeter/nanuq-more), where Polars expression
plugins are written in Nim. Polars, Python's or Nanuq's, calls them with
`ArrowArray`s and gets `ArrowArray`s back, so plugins read and write Arrow directly and
need no Rust at all. Its `polarsplugin/arrow.nim` defines the same structs again.

## Arrow in Nim today

Nanuq is not alone. A look around in November 2026:

| Project | What it does with Arrow | State |
| --- | --- | --- |
| [nimarrow](https://github.com/emef/nimarrow) | Arrays, tables and Parquet, on top of Arrow's GLib C API | Last commit July 2021 |
| [narrow](https://github.com/BontaVlad/narrow) | Much wider Arrow GLib bindings: arrays, tables, compute, Acero, Parquet, CSV, IPC, datasets, and C Data Interface export | Active (August 2026), version 0.0.1 |
| [NimDrake](https://github.com/BontaVlad/NimDrake) | DuckDB bindings, with zero-copy views over DuckDB's buffers and Arrow export through narrow (behind a feature flag) | Active, pre-alpha |
| Nanuq | Polars, C Data Interface in both directions, views | Since 0.6 |
| nanuq-more | Polars plugins in pure Nim | Prototype |

So there is already an Arrow implementation for Nim, more alive than expected:
narrow, with NimDrake as a real user. It wraps the reference C++ library, through
GLib, so it brings the whole Arrow feature set at the cost of a system dependency
(`libarrow-glib` and friends). What there isn't is a small, dependency-free layer that
everyone shares. Nanuq, nanuq-more and NimDrake each write their own copy of the
`ArrowSchema` and `ArrowArray` structs (NimDrake's comments explain why: the DuckDB
headers only forward-declare them). Datamancer and Arraymancer have their own column
and tensor layouts and don't speak Arrow at all.

## What a working Arrow layer would change

The scenarios below are ordered by size, and each one builds on the one before.

**0. Nothing changes.** This is a fine place to be. Polars does the heavy work in
Arrow already, the C Data Interface is there for anyone who needs it, and views cover
the hot read path. Most Nanuq users will never call `toArrow`.

**1. One shared package for the C Data Interface.** The three structs, their release
rules, and safe typed readers: validity bits, offsets for strings and lists, views for
`Utf8View`, children for structs. It would be pure Nim, a few hundred lines, with no
dependencies, against a spec that doesn't change: the Nim take on
[nanoarrow](https://arrow.apache.org/nanoarrow/). Nanuq, nanuq-more and NimDrake could
import it instead of defining the structs three times. The bigger win is that types
from different libraries would match, so data could flow between them without glue:

- a Nanuq frame into DuckDB through NimDrake, or a DuckDB result into Nanuq;
- a narrow table (Parquet, Acero) into Polars and back;
- in Nanuq, views for strings and nullable columns, not only numbers.

**2. Builders too.** Writing Arrow arrays from Nim, with a release callback that frees
Nim memory. This is what the last row of the benchmark needs: `mapElements`, `mapBatches`
and plugin results could be handed to Polars without the extra copy, and Nim UDFs
would get close to Rust ones. It would also allow zero-copy bridges in the other
direction: an Arraymancer tensor, or a Datamancer column, backed by a Polars buffer
(Arraymancer can already wrap foreign memory). The Datamancer and Arraymancer bridges
would then copy only when they really have to.

**3. A Nim engine that speaks Arrow.** On the same forum thread, Araq suggested a
different route: rather than wrapping Polars, generate the code you need, in Nim. The
[nanuqy](https://github.com/pietroppeter/nanuqy) experiment went that way and
translated a Polars kernel (`float_sum.rs`) into Nim that gives bit-for-bit the same
results. Kernels like that need a memory format, and Arrow is the obvious choice: a Nim
kernel working on Arrow buffers can be tested against Polars on the *same* memory, can
run as a Polars plugin today, and can stand on its own later. In this scenario Arrow
is what lets a Nim engine grow one kernel at a time, inside the existing ecosystem
instead of next to it.

**4. A full Arrow implementation in Nim.** IPC, Parquet, compute, datasets, all in
Nim. This is the one not to do. It's years of work, and Polars, DuckDB and narrow (via
Arrow C++) already cover it. The C Data Interface means a Nim program can use all of
them without owning any.

## Where this leaves Nanuq

The forum question gets a clear answer: Nanuq keeps the data in Arrow inside Polars,
crosses into Nim without copying where it can (`view`, `toArrow`), and copies where a
Nim `seq` is the point. The next step is scenario 1, and it is already in the Nanuq
backlog as *An Arrow C Data Interface package for Nim*. Two questions stay open. One
is whether the package should live on its own or grow out of narrow or NimDrake, whose
author already wrote the same structs. The other is how far into scenario 2 it should
go before it has a second user.
"""

nbSave
