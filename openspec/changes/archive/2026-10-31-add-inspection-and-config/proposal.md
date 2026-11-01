# Proposal

## Why

The first thing the 0.3 explainer does with a new table is look at it: one line per
column with `glimpse`, summary statistics with `describe`, and all 36 races of the
season printed at once, which needs more than Polars' default of 8 rows. Nanuq has none
of these. Python Polars has all three (`glimpse`, `describe`, `pl.Config`), and Rust
Polars reads its table limits from environment variables that Python's `Config` sets.

This is the second change of the 0.3 release, following the dev log "Designing Nanuq 0.3"
(section 7) and Pietro's follow-up on 2026-10-31: keep the four `setTbl*`-style setters
(one line with semicolons is fine) and also offer `setConfig(...)` and a scoped
`withConfig(...)`.

## What Changes

- **`glimpse(df, maxItemsPerColumn = 10, maxColnameLength = 50): string`**, Python's
  layout: `Rows:` and `Columns:`, then `$ name <dtype> v1, v2, ...` per column, strings
  quoted as Python's `repr` does. It returns the text (`echo df.glimpse`) instead of
  printing.
- **`describe(df, percentiles = [0.25, 0.5, 0.75], interpolation = Nearest): DataFrame`**:
  a `statistic` column (`count`, `null_count`, `mean`, `std`, `min`, the percentiles,
  `max`) and one column per input column, f64 for numeric and boolean columns, str
  for the others, built from expressions as Python Polars does. Also on `LazyFrame`.
- **Display config**, through the environment variables Rust Polars reads at every print:
  - setters `setTblRows(n)`, `setTblCols(n)`, `setTblWidthChars(n)`,
    `setFmtStrLengths(n)`; `-1` means no limit, `none(int)` restores the default;
  - `setConfig(tblRows = 12, tblCols = 10, tblWidthChars = 120, fmtStrLengths = 60)`,
    where an option left out stays as it is;
  - `resetConfig()` restores every default;
  - `withConfig(tblRows = 40): body` applies the options for the block and restores
    the previous values afterwards, also when the block raises.

## Capabilities

### New Capabilities
- `inspection`: `glimpse`, `describe` and the display config.

### Modified Capabilities

None.

## Differences from Polars

Expected differences from Polars' Rust and Python APIs:

- **`glimpse` returns a string** and never prints; Python prints by default and returns
  a string only with `return_type="string"`. `return_type="frame"` is left out (it needs
  List columns). Rust Polars has no `glimpse`.
- **`describe`** follows Python's output. Rust Polars dropped `describe`, so Nanuq builds
  it from expressions in Nim, the way Python's `LazyFrame.describe` does. Python's
  thousands separator for counts in string columns is not applied (Nanuq has no
  thousands separator setting yet). Temporal columns get their statistics with the
  temporal change.
- **Config** is a set of procs and a `withConfig` block, Nim's version of Python's
  `pl.Config` used as a function, a context manager or a decorator (no decorator). Only
  the four table options are covered; Python's other options (`tbl_formatting`,
  `float_precision`, `thousands_separator`, ...) are left for later. Rust Polars has no
  config API, only the environment variables (`POLARS_FMT_MAX_ROWS`,
  `POLARS_FMT_MAX_COLS`, `POLARS_TABLE_WIDTH`, `POLARS_FMT_STR_LEN`), which Nanuq sets.
- **Names** follow Python in camelCase: `set_tbl_rows` → `setTblRows`, `max_items_per_column`
  → `maxItemsPerColumn`.

## Impact

- `src/nanuq.nim`: `glimpse`, `describe`, the config procs and the `withConfig` macro.
  No change to the C ABI.
- `tests/test_inspection.nim` (new), added to `nanuq.nimble` and `.gitignore`.
- README lists the new procs.
