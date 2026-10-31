# Proposal

## Why

Real CSV files are rarely clean. They use `;` as a separator, mark missing values with
words like "lots" or "?", have a preamble before the header, need a column read as
another type, or come as a folder of daily files. Nanuq's `readCsv` handles only a
header row and null markers, and `writeCsv` has no options at all. Python Polars handles
all of these with keyword arguments, and its lazy `scan_csv` reads a glob of files without
loading them first. The 0.2 explainer post needs this in two scenes: it reads a season of
daily logs lazily, and it writes a report for a spreadsheet that expects `;` and decimal
commas.

This change takes up the "lazy `scanCsv`" part of the BACKLOG.md entry "More IO".
Parquet and JSON stay in the entry. It is the sixth and last change of the 0.2 release
(see the Polars coverage map, area "IO"). Pietro made the API choice on 2026-10-31 in
the doc "Nanuq 0.2: API choices the explainer forces": named arguments with Polars'
defaults, `schemaOverrides` taking `DataType` values, and a `char` separator.

## What Changes

- **`scanCsv(path, ...)`** returns a `LazyFrame`. `path` can be a glob such as
  `"logs/*.csv"`, and every matched file must have the same columns.
- **`readCsv(path, ...)`** takes the same options and returns a `DataFrame`.
  `readCsv(path)` and `readCsv(path, nullValues = [...])` keep working.
- **Read options**, named as in Python Polars and with its defaults:
  - `separator = ','`
  - `hasHeader = true`
  - `nullValues: openArray[string]`
  - `schemaOverrides: openArray[(string, DataType)]`, e.g. `{"bears": Int64}`
  - `skipRows = 0`
  - `nRows = none(int)`
  - `columns: openArray[string]` (read only these)
  - `inferSchemaLength = some(100)` (`none` scans every row)
  - `ignoreErrors = false`
  - `decimalComma = false`
- **`writeCsv(df, path, ...)` options**:
  - `separator = ','`
  - `includeHeader = true`
  - `nullValue = ""`
  - `quoteStyle = Necessary` (a pure enum `QuoteStyle`: `Necessary`, `Always`,
    `NonNumeric`, `Never`)
  - `floatPrecision = none(int)`
  - `decimalComma = false`
- `nRows`, `inferSchemaLength` and `floatPrecision` also accept a plain `int`, like
  `sample`'s `seed`.
- The ABI stays `0.2.0-dev`, and no Polars features are added (`lazy` and `csv` already
  include scanning and globs).

## Capabilities

### New Capabilities
- `csv-io`: reading, scanning and writing CSV with options.

### Modified Capabilities
- `native-bridge`: `NqQuoteStyle` joins the enums that keep the same order in Rust and
  `ffi.nim`.

## Differences from Polars

Expected differences from Polars' Rust and Python APIs:

- **Named arguments instead of Rust's builder.** Rust's `CsvReadOptions` and
  `LazyCsvReader` builders become named arguments, as in Python.
- **`separator` is a `char`** (`';'`), where Python takes a one-character string. A
  multi-character separator does not compile.
- **`schemaOverrides` takes `DataType` values** (`{"bears": Int64}`), like `cast`, not Nim
  types.
- **`quoteStyle` is an enum** (`quoteStyle = Always`), where Python takes a string.
- **Optional integers** (`nRows`, `inferSchemaLength`, `floatPrecision`) are
  `Option[int]`, and also accept a plain `int`.
- **`readCsv` is `scanCsv(...).collect`.** The two take the same options and read the same
  data. Python's `read_csv` has a separate eager reader with a few extra options.
- **A glob of files with different columns fails.** As in Polars, `scanCsv` expects the
  same columns in every file. Read the files separately and use
  `concat(how = Diagonal)` instead.
- **Not in this change:**
  - Read options: `quote_char`, `comment_prefix`, `encoding`, `try_parse_dates` (dates
    are not modelled yet), `row_index_name`, `truncate_ragged_lines`, `missing_utf8_is_empty_string`,
    and per-column `null_values` (a dict).
  - `schema` (the full schema) and `new_columns`.
  - CSV from a string (its own BACKLOG entry).
  - Write options: `quote_char`, the date and time formats, `float_scientific` and
    `line_terminator`.
- **Names** follow Polars in camelCase: `has_header` → `hasHeader`, `null_values` →
  `nullValues`, `schema_overrides` → `schemaOverrides`, `n_rows` → `nRows`, and so on.

## Impact

- `src/rust/src/lib.rs`:
  - `nq_lf_scan_csv` maps every read option onto `LazyCsvReader`. It replaces
    `nq_df_read_csv`.
  - `nq_df_write_csv` gains the write options.
  - New `#[repr(C)]` enum `NqQuoteStyle`.
- `src/nanuq/ffi.nim`, `src/nanuq.nim`: the declarations, `QuoteStyle`, `scanCsv`, and the
  new `readCsv` and `writeCsv` signatures.
- `tests/test_csv.nim`: each option, globs, and reading back what `writeCsv` wrote with
  the same options.
- `README.md` documents the options. `BACKLOG.md` keeps "More IO" for Parquet, JSON and
  `scanParquet`.
