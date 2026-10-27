# Tasks

## 1. CSV from a string

- [ ] 1.1 Add `nq_df_read_csv_str(data, len, null_values, n)` in Rust (Cursor over the bytes) and mirror it in `ffi.nim`; verify `cargo build --release` passes
- [ ] 1.2 Add `readCsvString(text, nullValues = [])` to `src/nanuq.nim`; verify with tests: same result as `readCsv` on `tests/data/with_na.csv`, null markers, and an empty-input error

## 2. Datasets module

- [ ] 2.1 Add `src/nanuq/data/penguins.csv` (palmerpenguins `inst/extdata/penguins.csv`) and `src/nanuq/data/README.md` with source, authors and CC0; verify the file has 345 lines
- [ ] 2.2 Add `src/nanuq/datasets.nim` with `penguins()` embedding the CSV via `staticRead` and reading it with `nullValues = ["NA"]`; verify with tests for shape, column order, null counts and dtypes, run from a different working directory

## 3. Penguins instead of iris

- [ ] 3.1 Rewrite the README example and its output, and `examples/basic.nim`, with penguins (e.g. mean body mass and count per species, after `dropNulls`); verify `nimble example` prints what the README shows
- [ ] 3.2 Switch the CSV read test in `tests/test_basic.nim` to penguins or the fixture, and update the `src/nanuq.nim` module doc example; verify `nimble test` passes
- [ ] 3.3 Check CI is green on the PR

## Workflow follow-up

- Archive the change: remove "Sample datasets" (and its penguins sub-item) from BACKLOG.md, and add a CHANGELOG line.
