# Tasks

## 1. Bridge

- [x] 1.1 Record the kind of the last error next to its message (`NqErrorKind`), unwrapping context; panics and Nanuq's own errors are `Generic`
- [x] 1.2 Export `nq_last_error_kind`; mirror it and the enum in `ffi.nim`

## 2. Nim API

- [x] 2.1 Rename `NanuqError` to `PolarsError` and add the subtypes; `raiseLast` raises the subtype, or `IOError` for IO
- [x] 2.2 Nanuq's own errors raise `InvalidOperationError`
- [x] 2.3 Rename everywhere (Datamancer module, tests, README, docs); tests for a missing column, a strict cast, a duplicate column, a missing file and `except PolarsError` catching subtypes

## 3. Docs and integration

- [x] 3.1 `nimble test` and `nimble specexamples` pass
- [x] 3.2 Archive the change and add CHANGELOG lines
