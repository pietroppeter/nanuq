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
  table (344 rows, 8 columns, "NA" read as null). The CSV (15 KB) is embedded in the
  binary at compile time, so loading needs no file path and no network.
- New `readCsvString(text, nullValues = [])`: reads CSV from a string, with the same
  options as `readCsv`. `penguins()` is built on it, and users get it too.
- The README example, `examples/basic.nim` and the CSV tests use penguins instead of
  iris. The dated dev-log posts stay as written, so `examples/iris_sample.csv` stays for
  them.

## Capabilities

### New Capabilities
- `datasets`: bundled sample datasets, how they are loaded, and their licensing.

### Modified Capabilities
- `dataframe-api`: an added requirement for reading CSV from a string.

## Differences from Polars

- **Bundled datasets.** Neither Polars (Rust or Python) nor pandas ship datasets. This
  follows the plotting libraries instead: seaborn's `load_dataset("penguins")`
  downloads and caches, Plotly Express bundles its data (`px.data.iris()`), and R
  bundles it in packages (`palmerpenguins::penguins`). Nanuq bundles its datasets
  because Nim can embed the file at compile time.
- **Same table as seaborn and R.** Columns and values match palmerpenguins'
  `penguins.csv` (the R package's data). Seaborn's copy has the same 344 rows but no
  `year` column and sex spelled `MALE` / `FEMALE`; Nanuq keeps the R version.
- **CSV from a string.** Python's `pl.read_csv` takes a path, bytes or a file-like
  object (`io.StringIO`), and Rust's `CsvReader` takes any `Read + Seek`. Nanuq has a
  separate `readCsvString` instead of overloading `readCsv`, because a Nim `string` is
  ambiguous between a path and content.

## Impact

- `rust/src/lib.rs`: `nq_df_read_csv_str(data, len, null_values, n)` reading from memory
  through a `Cursor`. Rebuilding the Rust library costs one CI run of about 4 min.
- `src/nanuq/ffi.nim` and `src/nanuq.nim`: the declaration and `readCsvString`.
- `src/nanuq/datasets.nim` and `src/nanuq/data/penguins.csv` (with a credit and CC0
  notice in `src/nanuq/data/README.md`). The data lives under `src/` so it ships with the
  package.
- `README.md`, `examples/basic.nim`, `tests/`: switch to penguins.
