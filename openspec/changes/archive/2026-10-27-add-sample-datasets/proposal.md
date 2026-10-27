# Proposal

## Why

Examples, tests and docs need small, well-known data that loads with one call and no
path. Today they read `examples/iris_sample.csv`, a 12-row iris sample found by
relative path. Pietro wants penguins
([palmerpenguins](https://allisonhorst.github.io/palmerpenguins/), CC0) instead of iris.
Penguins is also a better showcase now that Nanuq supports nulls: it has missing values
in five columns.

This takes up the BACKLOG.md entry "Sample datasets" (Datasets), including its sub-item
"Replace iris with penguins".

## What Changes

- New module `nanuq/datasets` with `penguins(): DataFrame`, the full palmerpenguins
  table (344 rows, 8 columns, "NA" read as null). It calls `readCsv` on the CSV that ships
  next to the module, with the path fixed at compile time (`currentSourcePath`), so it
  works from any working directory and needs no network and no change to the Rust bridge.
  This is a convenience while Nanuq is young; the datasets are expected to move out later.
- The README example, `examples/basic.nim` and the CSV tests use penguins instead of
  iris. (During implementation Pietro asked to switch the two dev-log posts to penguins
  too and remove `examples/iris_sample.csv`.)

## Capabilities

### New Capabilities
- `datasets`: bundled sample datasets, how they are loaded, and their licensing.

### Modified Capabilities
None.

## Differences from Polars

- **Bundled datasets.** Neither Polars (Rust or Python) nor pandas ship datasets. This
  follows the plotting libraries instead: seaborn's `load_dataset("penguins")`
  downloads and caches, Plotly Express bundles its data (`px.data.iris()`), and R
  bundles it in packages (`palmerpenguins::penguins`). Bundling in Nanuq is a
  convenience for early development, not a design choice. Once the library matures,
  the datasets will probably be dropped and vendored from elsewhere (see the backlog).
- **Same table as seaborn and R.** Columns and values match palmerpenguins'
  `penguins.csv` (the R package's data). Seaborn's copy has the same 344 rows but no
  `year` column and sex spelled `MALE` / `FEMALE`; Nanuq keeps the R version.
- **Not embedded.** Embedding the CSV with `staticRead` would make binaries
  self-contained, but needs a read-CSV-from-string function in the bridge. Since the
  datasets are temporary, `penguins()` reads the file instead: a compiled program needs
  the Nanuq sources on disk where it was built. Reading CSV from memory (Python's
  `pl.read_csv(io.StringIO(...))`) stays in the backlog.

## Impact

- No change to `rust/src/lib.rs` or `ffi.nim`, so CI needs no Rust rebuild.
- `src/nanuq/datasets.nim` and `src/nanuq/data/penguins.csv` (with a credit and CC0
  notice in `src/nanuq/data/README.md`). The data lives under `src/` so it ships with the
  package.
- `README.md`, `examples/basic.nim`, `tests/`: switch to penguins.
