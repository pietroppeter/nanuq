# Proposal

## Why

In nimib documents a DataFrame can only be shown as Polars' text table. That table is
the reference output and stays the default in the dev log (it is also a check that Nanuq
prints exactly what Polars prints). For pages where a real HTML table reads better, Nanuq
should offer the same HTML table that Python Polars shows in Jupyter.

This takes up the BACKLOG.md entry "nimib integration" (Ecosystem).

## What Changes

- New `toHtml(df, maxRows = 10, maxCols = 75): string`, a port of Python Polars'
  `DataFrame._repr_html_`. It returns the same HTML, with the same information:
  - `shape: (344, 8)` above the table, with `_` thousand separators;
  - a header row of column names and a row of dtypes (`str`, `i64`, `f64`, …);
  - when there are more rows or columns than the limits, the first and last ones
    around a `…` row or column (10 rows show as 5, `…`, 5);
  - each cell formatted by Polars itself, as Python shows it: floats as in the text
    table, strings in quotes and cut after 30 characters with `…`, nulls as `null`;
  - HTML escaping, and the small `<style>` block and `dataframe` class Python emits.
- It works in any HTML context. In nimib it is used as `nbRawHtml: df.toHtml`, so
  Nanuq does not depend on nimib. The Nanuq theme gets CSS for `table.dataframe`.
- A new bridge function returns one cell formatted the way Python's `get_fmt` does
  (`AnyValue`'s Display, with the string cut).
- The dev log uses it sparingly: one short section in "How Nanuq works" shows the same
  result as text and as HTML. Every other output stays Polars' text table.

## Capabilities

### New Capabilities
None.

### Modified Capabilities
- `dataframe-api`: an added requirement for HTML tables.
- `native-bridge`: an added requirement for formatted cells.

## Differences from Polars

- **Rust** has no HTML output; this follows Python.
- **Python** calls it `_repr_html_` and reads the limits from the `POLARS_FMT_MAX_ROWS`,
  `POLARS_FMT_MAX_COLS` and `POLARS_FMT_STR_LEN` environment variables. Nanuq names it
  `toHtml` and takes the row and column limits as parameters with Python's defaults
  (10 and 75); the string length is fixed at Python's default (30). The
  `POLARS_FMT_TABLE_HIDE_*` switches are not supported.
- **HTML vs text table.** As in Python, the HTML defaults differ from the text table:
  the text table shows at most 8 columns, the HTML table 75. Rows match (10).

## Impact

- `src/rust/src/lib.rs` and `src/nanuq/ffi.nim`: one new function. This changes the Rust
  library, so it needs a library build. `lib-v0.1.0` is already released without it, so
  `toHtml` ships with the next library release (e.g. `lib-v0.1.1`); until then it works
  only with a local cargo build.
- `src/nanuq.nim`: `toHtml`. `docs/nanuqtheme.nim`: table CSS. `docs/blog/how_nanuq_works.nim`.
- New tests in `tests/`.
