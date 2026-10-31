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

- **More IO** (M): Parquet, JSON, lazy `scanCsv` / `scanParquet`.
- **More dtypes** (M): dates and datetimes, categoricals.
- **More expressions** (M): string functions (conditionals and `over` landed in 0.2).

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
- **Arraymancer tensors** (S). Copy numeric columns to and from `Tensor[T]` for numerical
  work.

## Datasets

- **Unbundle the datasets** (S). `nanuq/datasets` bundles penguins as a convenience for
  early development. Once Nanuq matures, drop the data from the library and vendor it
  from elsewhere (a separate package, or download and cache, like seaborn's
  `load_dataset`).
- **CSV from a string or bytes** (S). Like Python's `pl.read_csv(io.StringIO(...))`.
  Would also let datasets be embedded with `staticRead` for self-contained binaries.
  Needs a new bridge function (Cursor over the bytes).

## Docs

- **Cache rendered dev-log posts in CI** (S). Today the docs job reinstalls nimib and
  ggplotnim and re-renders every post on each run, which grows with each post. Cache
  each post's HTML (and images) keyed by a hash of the post, `docs/nanuqtheme.nim`,
  `src/` and `rust/`, and render only the posts whose key changed. Old posts keep acting
  as a compile check when the API changes. (Freezing old posts as committed HTML is
  simpler but loses that check.)
- **0.2 explainer post** (S-M). A dev-log post with a playful, non-trivial example of
  the whole 0.2 release, written once 0.2 is out. A first draft covering only data
  types and casts ("The great polar bear census": a messy ranger field log from four
  Svalbard stations) was taken out of #26; the idea is to be reconsidered then, e.g.
  extended with joins (station coordinates), frame verbs and conditional expressions.
- **Official documentation** (L). A reference and guides, separate from the dev log.

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
