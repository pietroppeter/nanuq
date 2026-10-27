# Tasks

## 1. Datasets module

- [x] 1.1 Add `src/nanuq/data/penguins.csv` (palmerpenguins `inst/extdata/penguins.csv`) and `src/nanuq/data/README.md` with source, authors and CC0; verify the file has 345 lines
- [x] 1.2 Add `src/nanuq/datasets.nim` with `penguins()` calling `readCsv` on `currentSourcePath.parentDir / "data" / "penguins.csv"` with `nullValues = ["NA"]`; verify with tests for shape, column order, null counts and dtypes, run from a different working directory

## 2. Penguins instead of iris

- [x] 2.1 Rewrite the README example and its output, and `examples/basic.nim`, with penguins (e.g. mean body mass and count per species, after `dropNulls`); verify `nimble example` prints what the README shows
- [x] 2.2 Switch the CSV read test in `tests/test_basic.nim` to penguins or the fixture, and update the `src/nanuq.nim` module doc example; verify `nimble test` passes
- [x] 2.3 Check CI is green on the PR

## Workflow follow-up

- Archive the change: remove "Sample datasets" (and its penguins sub-item) from BACKLOG.md, and add a CHANGELOG line.
