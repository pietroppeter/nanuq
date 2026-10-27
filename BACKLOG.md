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

- **Prebuilt binaries for users** (M). A release workflow builds `libnanuq_ffi` for
  Linux x64, macOS arm64 and Windows and attaches it to GitHub Releases. `ffi.nim`
  downloads the one matching the package version at compile time and falls back to
  cargo. This removes the ~10 minute first build for users.
- **`nimble install` support** (S-M). Today the package expects `rust/` next to `src/`.
  Pairs with prebuilt binaries.
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
- **Nulls and more dtypes** (M): null handling (`Option`), dates and datetimes,
  categoricals.
- **More expressions** (M): `when/then/otherwise`, string functions, casting, window
  functions (`over`).
- **Column access as Nim seqs without per-cell calls** (S). Bulk copy instead of
  `toSeq` reading cell by cell.

## Ecosystem

- **Plotting with ggplotnim** (S-M). Checked in ggplotnim's source (2026-10-27): its
  only entry point is `ggplot(data: DataFrame, aes)` with a Datamancer DataFrame, and
  ggplotnim depends on Datamancer and Arraymancer anyway. There is no seq-based input.
  Datamancer does build a DataFrame straight from seqs (`toDf({"x": xs, "y": ys})`),
  so options, from simplest to leanest:
  1. *Seqs into `toDf`, no glue code.* `toDf({"x": df.toSeq("x", float), ...})`. This
     works today but copies through seqs and reads cells one by one (see "Column access
     as Nim seqs" under API).
  2. *A small optional module* (`nanuq/ggplot`, so the core doesn't depend on Datamancer).
     A `ggplot(df: nanuq.DataFrame, aes(...))` overload converts only the columns named
     in `aes`. Users can also aggregate in Polars first and convert the small result.
  3. *Zero-copy.* Once columns cross through the Arrow C Data Interface (see Bridge), wrap
     Polars buffers as tensors without copying. Only worth it for very large plots.
  Start with 2, after bulk column access.
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

## Docs

- **Blog index page** (S). A list of dev-log posts instead of redirecting to the
  latest one.
- **Official documentation** (L). A reference and guides, separate from the dev log.
