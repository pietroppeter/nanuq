# Tasks

## 1. Bridge

- [x] 1.1 Add the Polars features `strings`, `regex`, `string_pad`, `string_reverse`, and `concat_str`
- [x] 1.2 Add `nq_expr_str` with `NqStrOp`, and `nq_expr_concat_str`; mirror them in `ffi.nim`

## 2. Nim API

- [x] 2.1 Add `StrNameSpace`, `str` and every function listed in the proposal
- [x] 2.2 Add `concatStr` and `format`
- [x] 2.3 Write `tests/test_strings.nim`: each function, literal vs regex, strict vs not, nulls, `join` in `agg`, `format` with too few or too many arguments, `format` next to `strutils`; add it to `nanuq.nimble` and `.gitignore`

## 3. Docs and integration

- [x] 3.1 README lists the namespace; `nimble test` and `nimble specexamples` pass
- [x] 3.2 Archive the change: remove BACKLOG "More expressions", add CHANGELOG lines
