# Proposal

## Why

Excel is how much tabular data arrives: the 0.6 book map counts 9 sections that need
`read_excel`/`write_excel` (user guide io/excel, O'Reilly ch6 and ch13, Packt ch2), and
BACKLOG.md "More IO" lists Excel. Rust Polars has no Excel support, so the crate adds
two pure-Rust crates, compiled into the same static library as Polars: calamine to read
and rust_xlsxwriter to write. Nothing outside the library is needed at run time.

It is the sixth change of the 0.6 release (the fifth, a formula macro, was dropped). It
takes the Excel part of the BACKLOG.md entry "More IO".

## What Changes

- `readExcel(path, sheetName, sheetId = 1, hasHeader, skipRows, columns,
  schemaOverrides)`: one sheet of an .xlsx, .xlsm, .xlsb, .xls or .ods file, with column
  types inferred from the cells (Boolean, Int64, Float64, Date, Datetime[ms], String).
- `readExcelSheets(path)`: every sheet, by name.
- `writeExcel(df, path, worksheet = "Sheet1", includeHeader, autofit, floatPrecision)`:
  one worksheet in a new .xlsx file.

## Capabilities

### New Capabilities
- `excel-io`: reading and writing Excel workbooks.

## Differences from Polars

- Python picks an engine (`calamine` through the Python package fastexcel by default,
  `openpyxl`, `xlsx2csv`) and writes through the Python package xlsxwriter. Nanuq has
  one built-in reader (the calamine crate) and one writer (the rust_xlsxwriter crate).
- `read_options={"skip_rows": n}` and `has_header` become `skipRows` and `hasHeader`
  parameters; there is no `engine_options`, `infer_schema_length` or `drop_empty_rows`.
- `sheet_id = 0` (all sheets as a dict) is `readExcelSheets`; `sheet_name` as a list is
  not supported.
- `write_excel` writes a plain sheet: header in bold, numbers, booleans, dates and
  datetimes as Excel values, everything else as text. Python's table styles,
  conditional formats, sparklines, formulas, column widths and positions are left out,
  as is writing into an existing workbook.
- Date cells at midnight read as Date, other date-times as Datetime[ms]; Python's
  fastexcel follows the cell format instead.

## Impact

- `src/rust/Cargo.toml`: `calamine` (feature `dates`), `rust_xlsxwriter`, `chrono`.
  The static library and the release archives grow by a few MB.
- `src/rust/src/lib.rs`, `src/nanuq/ffi.nim`: `nq_read_excel`, `nq_excel_sheet_names`,
  `nq_write_excel`.
- New `tests/test_excel.nim`.
