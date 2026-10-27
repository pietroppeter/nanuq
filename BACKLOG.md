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

- **Sample datasets** (S-M). *In progress in OpenSpec change `add-sample-datasets`.*
  Small, well-known datasets for examples, tests and the docs,
  loadable with one call (e.g. `import nanuq/datasets; let df = penguins()`).
  How others do it:
  - *Bundled in the package*: R's `datasets`, ggplot2 (`mpg`, `diamonds`), Plotly
    Express (`px.data.iris()`, gzipped CSVs) and scikit-learn's `load_iris`.
  - *Downloaded and cached on first use*: seaborn's `load_dataset("penguins")` (from the
    `seaborn-data` GitHub repo, cached under `~/seaborn-data`) and scikit-learn's
    `fetch_*` for larger sets. vega_datasets mixes both.
  - *Plain files in the repo, read by path*: ggplotnim (`data/mpg.csv`). Polars and pandas
    ship none, and their docs read CSVs from URLs.
  For Nanuq, the simplest is CSVs in the repo plus a small module. In Nim, `staticRead`
  can embed the CSV in the binary, so loading needs no path and no network. That needs
  a read-CSV-from-string function in the bridge. Keep the bundled sets small and
  download anything large.
  - **Replace iris with penguins** ([palmerpenguins](https://allisonhorst.github.io/palmerpenguins/),
    CC0, 344 rows) in the examples, tests and dev log. Penguins has missing values, so it
    loads with `readCsv(path, nullValues = ["NA"])` now that nulls are supported.

## Docs

- **Blog index page** (S). A list of dev-log posts instead of redirecting to the
  latest one.
- **Official documentation** (L). A reference and guides, separate from the dev log.
