# Tasks

## 1. Nim API

- [x] 1.1 Add `glimpse` with Python's layout and value formatting
- [x] 1.2 Add `describe` on DataFrame and LazyFrame with `percentiles` and `interpolation`
- [x] 1.3 Add `setTblRows`, `setTblCols`, `setTblWidthChars`, `setFmtStrLengths`, `setConfig`, `resetConfig` and the `withConfig` macro
- [x] 1.4 Write `tests/test_inspection.nim` (glimpse truncation and quoting, describe on numeric, bool and string columns and custom percentiles, setters, `withConfig` restoring after an exception); add it to `nanuq.nimble` and `.gitignore`

## 2. Docs and integration

- [x] 2.1 README lists the new procs; `nimble test` and `nimble specexamples` pass
- [x] 2.2 Archive the change and add CHANGELOG lines
