# Backlog

Ideas and possible next steps for Nanuq.

Lifecycle of an idea:
1. It starts here.
2. When it is picked up, it becomes an OpenSpec change (`/opsx:propose`, under
   `openspec/changes/`). The entry stays here, marked *in progress* with the change name.
3. When the change is implemented and archived (`/opsx:archive`), the entry is removed
   from this file and a line is added to [CHANGELOG.md](CHANGELOG.md).

Each entry says what the idea is and why it matters. Rough size: S (hours), M (a day or
two), L (more).

## Distribution

- **Shared library option** (M). Ship `.so` / `.dylib` / `.dll` instead of the static
  lib (about 300 MB unstripped), with runtime loading.

## Performance

- **Build the prebuilt lib with nightly Rust, the `nightly` Polars feature and jemalloc**
  (S-M, *planned for 0.3*). Nanuq 0.2 is 2.5-4.5x slower than Python Polars on the same
  queries (nanuq-book benchmarks, PDS-H SF1 from CSV), with up to 2 s extra on every query
  that reads `lineitem.csv`. Python Polars is built with a nightly toolchain and the
  `nightly` feature, which turns on `simd` (among others the portable-SIMD CSV parser in
  `polars-io`), and with jemalloc as global allocator. Measured on 2026-10-31, `dist`
  profile, total of 13 queries, best of 3:

  | lib | Linux sandbox (4-core Xeon) | M3 Pro |
  |---|---|---|
  | prebuilt lib-v0.2.0 | 27.8 s | 13.6 s |
  | nightly + `nightly` | 13.0 s | 3.56 s |
  | + jemalloc (`#[global_allocator]`) | | 3.20 s |
  | Python Polars 2.1, in-memory | 11.2 s | 3.07 s |

  `performant`, `streaming`/`cse`, the streaming engine and Polars built from git at
  py-2.1.0 made no measurable difference; jemalloc via `LD_PRELOAD` did nothing on
  Linux. The work: opt-in crate features `nightly = ["polars/nightly"]` and `jemalloc`
  (stable cargo fallback and CI unchanged), release-lib.yml builds with a pinned nightly
  and both features, check all release targets. The rest of the gap is q21, where the
  Nim port needs an extra group-by and join until Nanuq has `Expr.filter`.

## Bridge

- **Generate `ffi.nim` with nbindgen** (S-M). Generate the Nim declarations from the
  Rust code instead of writing them by hand, and add a CI check that the generated file
  is up to date. Pietro said yes, but not yet (2026-10-27). Weighed on 2026-10-28, from
  nbindgen's source and test expectations (master, last commit 2023-10-20, rebased on
  cbindgen 0.26; crates.io only has 0.0.1 from 2020, so it would be built from git):
  - *Not a blocker for 0.1.* The generated file would only replace the declarations at
    the end of `ffi.nim`; the linking logic stays hand-written, and neither users nor
    the prebuilt archives would see a difference. nbindgen would run in CI only, never
    on a user's machine.
  - *Its output needs fixing first.* Enum discriminants are dropped (the code writing
    them is commented out), `*const c_char` becomes `ptr char` instead of `cstring`, and
    procs get `importc` without `cdecl`. Our enums start at 0 with no holes, so today
    only the `cstring` mapping matters, but it touches most of the API. Options: a small
    post-processing step, or patching nbindgen (a fork, or upstream).
  - *What it buys.* The ~70 declarations can't drift from `lib.rs` (types, argument
    order, enum order, which today only a comment keeps in sync). A cheaper guard
    without nbindgen: a test that every `importc` name in `ffi.nim` is exported by
    `libnanuq_ffi.a` (`nm`), plus a Rust test of the enum values.
  - *Decided (Pietro, 2026-10-28).* Not now: `ffi.nim` stays hand-written. If taken up
    later, nbindgen would be used from our own fork, so fixes don't wait on upstream.
- **Zero-copy columns through the Arrow C Data Interface** (L). Move whole columns
  between Nim and Polars without copying.

## API

- **More IO** (M): NDJSON, Excel, writing to streams, sink functions (streaming writes),
  cloud storage. (CSV, Parquet, IPC and reading streams are done.)
- **More dtypes** (M): lists, structs, decimals, binary.
- **Smaller Polars functions found by the 0.4 book ports** (S each). `over(...,
  mappingStrategy)`; Expr `shuffle` and `sample`; `hash`; `get(i)` (today `gather([i])`);
  `argTrue`; `upperBound`/`lowerBound`; `extendConstant`; `partitionBy(asDict = true)`.
- **Print dtypes as Python does** (S, discussion first). `$dtype` gives Rust's `i64`;
  Python prints `Int64`. Matching Python would help readers who compare outputs, but
  frame headers print `i64` in both.

## Ecosystem

- **Plotting with ggplotnim** (S-M). Checked in ggplotnim's source (2026-10-27): its
  only entry point is `ggplot(data: DataFrame, aes)` with a Datamancer DataFrame, and
  ggplotnim depends on Datamancer and Arraymancer anyway. There is no seq-based input.
  Datamancer does build a DataFrame straight from seqs (`toDf({"x": xs, "y": ys})`),
  so options, from simplest to leanest:
  1. *Seqs into `toDf`, no glue code.* `toDf({"x": df.toSeq("x", float), ...})`. This
     works today and copies each column once (one FFI call per column).
  2. *A small optional module* (`nanuq/ggplot`, so the core doesn't depend on Datamancer).
     A `ggplot(df: nanuq.DataFrame, aes(...))` overload converts only the columns named
     in `aes`. Users can also aggregate in Polars first and convert the small result.
  3. *Zero-copy.* Once columns cross through the Arrow C Data Interface (see Bridge), wrap
     Polars buffers as tensors without copying. Only worth it for very large plots.
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

## Datasets

- **Unbundle the datasets** (S). `nanuq/datasets` bundles penguins as a convenience for
  early development. Once Nanuq matures, drop the data from the library and vendor it
  from elsewhere (a separate package, or download and cache, like seaborn's
  `load_dataset`).

## Docs

- **Cache rendered dev-log posts in CI** (S). Today the docs job reinstalls nimib and
  ggplotnim and re-renders every post on each run, which grows with each post. Cache
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
