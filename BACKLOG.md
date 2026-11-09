# Backlog

Ideas for future development of Nanuq. This is a loose list, not a roadmap: entries
can be stale, and nothing here is committed. For what Polars has and Nanuq still lacks,
see the [Polars coverage map](https://pietroppeter.github.io/nanuq/polars_coverage.html).

When an idea is picked up it becomes an OpenSpec change (`/opsx:propose`) and is marked
*in progress* here with the change name. Once implemented and archived, its entry is
removed and a line goes to [CHANGELOG.md](CHANGELOG.md).

Rough size: S (hours), M (a day or two), L (more).

## Distribution

- **Shared library option** (M). Ship `.so` / `.dylib` / `.dll` instead of the static
  lib (about 300 MB unstripped), with runtime loading.
- **Smaller libraries: Cargo features per area** (M). The 0.6 lib is a ~286 MB `.a`
  (fat LTO) and a stripped Nim program linked against it is about the size of
  py-polars' own library (178 MB `.so`). Every Polars feature in `Cargo.toml` is built
  in whether a program uses it or not, and the linker drops only whole object files
  (a program that never reads Excel still carries ~2 MB of calamine/xlsxwriter).
  Options: Cargo features per area (`excel`, `sql`, `json`, `serde`, ...) selected with
  `-d:nanuqFeatures=...` for source builds, with the Nim side hiding procs whose
  feature is off; and/or a "lean" prebuilt variant next to `-legacy-cpu`. Measure a
  stripped, LTO-linked binary each release, next to py-polars. (Pietro asked about
  size and a separate Excel lib, 2026-11-01: a separate lib would link Polars twice.)

## Bridge

- **Generate `ffi.nim` with nbindgen** (S-M, *decided not now*, Pietro 2026-10-28).
  Generating the Nim declarations from the Rust code would stop them drifting from
  `lib.rs`, but nbindgen is unmaintained (last commit 2023) and its output needs fixing
  first (enum discriminants dropped, `ptr char` instead of `cstring`, no `cdecl`). If
  taken up, use our own fork and run it in CI only. A cheaper guard without it: a test
  that every `importc` name in `ffi.nim` is exported by `libnanuq_ffi.a` (`nm`), plus a
  Rust test of the enum values.

## API

- **More IO** (M): databases other than SQLite (PostgreSQL, MySQL), Avro, writing to
  Nim streams. (CSV, Parquet, IPC, JSON/NDJSON, Excel, ODS, SQLite, cloud storage,
  reading streams and sinks are done.)
- **Smaller coverage gaps** (S-M). The partial rows of the coverage map: `mapRows`
  and `LazyFrame.mapBatches`, `concat` with `align`.
- **Nim sugar for expressions** (M, design first). Considered for 0.6 as a formula
  macro and dropped (Pietro, 2026-11-01): Polars expressions are already expressive,
  and any Nim sugar should be Nanuq's own design, not Datamancer's `f{}` route. Revisit
  only with concrete cases where the method chains read badly.

## Ecosystem

- **Plotting** (S-M). The one feature group the coverage map gives priority P1. Today
  plots go through `toSeq` (nim-plotly, used by the explainers) or `toDatamancer`
  (ggplotnim); there is no `df.plot` namespace. For ggplotnim, checked in its source
  (2026-10-27): its only entry point is `ggplot(data: DataFrame, aes)` with a Datamancer DataFrame, and
  ggplotnim depends on Datamancer and Arraymancer anyway. There is no seq-based input.
  Datamancer does build a DataFrame straight from seqs (`toDf({"x": xs, "y": ys})`),
  so options, from simplest to leanest:
  1. *Seqs into `toDf`, no glue code.* `toDf({"x": df.toSeq("x", float), ...})`. This
     works today and copies each column once (one FFI call per column).
  2. *A small optional module* (`nanuq/ggplot`, so the core doesn't depend on Datamancer).
     A `ggplot(df: nanuq.DataFrame, aes(...))` overload converts only the columns named
     in `aes`. Users can also aggregate in Polars first and convert the small result.
  3. *Zero-copy.* Since 0.6 columns cross through the Arrow C Data Interface (`view`,
     `toArrow`), so Polars buffers could back tensors without copying. Only worth it
     for very large plots.
  Start with 2 (bulk column access is done). Option 1 is shown, with open questions, in
  the dev log post "Plotting with ggplotnim" (`docs/blog/plotting_with_ggplotnim.nim`).
- **A Narwhals-style dataframe API for Nim** (L, exploratory). Like Python's
  [Narwhals](https://narwhals-dev.github.io/narwhals/): a backend-agnostic layer (a Nim
  `concept` or a thin wrapper) with a Polars-like subset of operations, implemented by
  Nanuq and Datamancer. Libraries such as ggplotnim could then accept either DataFrame
  without converting, which would replace the conversion options above. One hook to look
  at: Datamancer's `DataTable[C]` is already generic over a `ColumnLike` concept.
  Open questions:
  is it compile-time (concepts and generics) or runtime (variant/ref), which subset of
  operations goes in, and how expressions are represented.
- **An Arrow C Data Interface package for Nim** (M, exploratory). The standard
  `ArrowSchema`/`ArrowArray`/`ArrowArrayStream` structs are defined twice today, in
  `src/nanuq/ffi.nim` and in nanuq-more's `polarsplugin/arrow.nim`. A small standalone
  pure-Nim package (a Nim take on nanoarrow) could hold them for both, and for any Nim
  code talking to DuckDB or other Arrow libraries. Layers: (1) the structs plus safe typed
  readers (validity bitmaps, string and list offsets); (2) builders, so Nim UDF results,
  strings and plugin outputs could be handed to Polars without a copy (today only numeric
  no-null input is zero-copy, through `view`). Not full Arrow (IPC, compute): Polars,
  DuckDB and arrow-glib cover that. Others to talk to first:
  [narrow](https://github.com/BontaVlad/narrow) (Arrow GLib bindings, active in 2026) and
  [NimDrake](https://github.com/BontaVlad/NimDrake) (DuckDB), which define the same
  structs. Scenarios in the dev-log post "What about Arrow?".

## Datasets

- **Unbundle the datasets** (S). `nanuq/datasets` bundles penguins as a convenience for
  early development. Once Nanuq matures, drop the data from the library and vendor it
  from elsewhere (a separate package, or download and cache, like seaborn's
  `load_dataset`).

## Docs

- **Cache rendered dev-log posts in CI** (S). Since one-program-builds (#67) the docs
  job caches its packages and renders the site as one program (`docs/all.nim`), but it
  still re-renders every post on each run, which grows with each post. Cache
  each post's HTML (and images) keyed by a hash of the post, `docs/nanuqtheme.nim`,
  `src/` and `rust/`, and render only the posts whose key changed. Old posts keep acting
  as a compile check when the API changes. (Freezing old posts as committed HTML is
  simpler but loses that check.)
- **Official documentation** (L). A reference and guides, separate from the dev log.
- **One shared repo for the docs theme and the Nim/Python machinery** (M). The same
  pieces now live twice: the dev-log theme (`docs/nanuqtheme.nim`) and the nanuq-book
  theme (`book/nanuqbook.nim`, `theme/`), and the 👑 Nim / 🐍 Python tabs, written once in
  the book (Python run live via nimpy, frame HTML compared) and again in the 0.4 explainer
  `docs/blog/counting_el_ninos.nim` (Python code and outputs recorded by `expected.py`,
  text and Plotly figures compared). Move them into one small Nimble package that both
  repos use: theme (CSS, fonts, highlighting), tabs with both Python modes (live or
  recorded), output checks, and the jupytext cell reader. Fixes to one stop drifting from
  the other.

## CI

- **Bump GitHub Actions to Node 24 majors** (S, low priority). Runs warn that
  `actions/checkout@v4` targets the deprecated Node 20 and is forced onto Node 24. It
  still works, so nothing is broken yet. Bump checkout (v5+) and the artifact, cache and
  pages actions to their Node 24 majors, check `jiro4989/setup-nim-action`,
  `dtolnay/rust-toolchain` and `Swatinem/rust-cache`, and confirm CI stays green.

## Nim tooling

- **Decide whether to use Atlas** (S, discussion first). Atlas is the dependency manager
  that ships with Nim 2.x, next to Nimble. Talk through whether Nanuq should use it, for
  development, docs and CI, or keep Nimble only. Weigh how it would change install for
  users and the `nanuq.nimble` tasks. Raised by Pietro on 2026-10-30.
