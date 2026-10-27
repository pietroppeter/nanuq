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

- **Prebuilt binaries for users** (M). *In progress in OpenSpec change
  `ship-prebuilt-binaries`.* Removes the ~10 minute first build for users.
  Researched 2026-10-27 (Explorer/rustler_precompiled, r-polars, nwaku's `librln`,
  Julia JLLs, Zig, Go, Node, Ruby, Deno), written up in the dev log post "Shipping the
  Rust half" (`docs/blog/shipping_rust_binaries.nim`). The plan that came out of it:
  - *Release.* A workflow on `lib-v*` tags builds the static lib for
    `x86_64-unknown-linux-gnu` and `aarch64-unknown-linux-gnu` (glibc 2.28 floor),
    `aarch64-apple-darwin` and `x86_64-pc-windows-gnu` (gnu, so it links with Nim's
    default MinGW), and attaches `libnanuq_ffi-<libver>-<triple>.tar.gz` plus SHA-256 sums.
  - *Versioning.* The lib version is `rust/Cargo.toml`'s, separate from the Nim package
    version, so Nim-only releases reuse the last lib. Sums are committed (e.g.
    `rust/lib-sums.txt`). A `-dev` lib version never downloads, and CI fails if `rust/`
    changed without a version bump. Rust exports `nq_version()` for a runtime check.
  - *Download.* At compile time in `ffi.nim`, not in a nimble hook (Atlas, nimby and git
    clones don't run hooks): `nanuqLibDir`, then local cargo output, then a user cache
    (`~/.cache/nanuq/<libver>/<triple>/`), then `curl` + `tar` + checksum, then cargo.
    `-d:nanuqLib=auto|prebuilt|source` picks the policy. A checksum mismatch is an
    error, every other miss falls back to cargo with a hint.
  - *Decided (Pietro, 2026-10-27).* Download by default (`auto`). Windows is MinGW
    (`-gnu`) only for now. Lib releases are tagged by hand. CPU variants as Explorer
    does: x86_64 targets ship a modern build (x86-64-v3, AVX2/FMA) and a `legacy-cpu`
    baseline build. On Linux `ffi.nim` reads `/proc/cpuinfo` at compile time and picks
    legacy when a flag is missing; elsewhere legacy is only chosen with
    `-d:nanuqLegacyCpu`, which also forces it everywhere (e.g. when building for older
    machines than the build host). arm64 targets have one build.
  - *Before implementing.* Measure the archive size with `lto = "fat"`.
- **`nimble install` support** (S-M). *In progress in OpenSpec change
  `ship-prebuilt-binaries`* (the crate moves to `src/rust/`, since nimble installs only
  `srcDir`).
- **Shared library option** (M). Ship `.so` / `.dylib` / `.dll` instead of the static
  lib (about 300 MB unstripped), with runtime loading.

## Bridge

- **Generate `ffi.nim` with nbindgen** (S-M). Generate the Nim declarations from the
  Rust code instead of writing them by hand, and add a CI check that the generated file
  is up to date. Pietro said yes, but not yet (2026-10-27).
- **Zero-copy columns through the Arrow C Data Interface** (L). Move whole columns
  between Nim and Polars without copying.

## API

- **More IO** (M): Parquet, JSON, lazy `scanCsv` / `scanParquet`.
- **Joins** (M): inner, left, outer, cross.
- **More dtypes** (M): dates and datetimes, categoricals.
- **More expressions** (M): `when/then/otherwise`, string functions, casting, window
  functions (`over`).

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
- **Datamancer interop both ways** (S). `toDatamancer` / `fromDatamancer`, so existing
  Datamancer code can use Polars for the heavy queries.
- **nimib integration** (S). Render a DataFrame as an HTML table in nimib documents
  (`nbDataFrame` or a `toHtml` proc) instead of the text table.
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

- **Blog index page** (S). A list of dev-log posts instead of redirecting to the
  latest one.
- **Cache rendered dev-log posts in CI** (S). Today the docs job reinstalls nimib and
  ggplotnim and re-renders every post on each run, which grows with each post. Cache
  each post's HTML (and images) keyed by a hash of the post, `docs/nanuqtheme.nim`,
  `src/` and `rust/`, and render only the posts whose key changed. Old posts keep acting
  as a compile check when the API changes. (Freezing old posts as committed HTML is
  simpler but loses that check.)
- **Official documentation** (L). A reference and guides, separate from the dev log.
