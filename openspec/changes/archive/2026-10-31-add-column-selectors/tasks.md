# Tasks

## 1. Bridge

- [x] 1.1 Add `#[repr(C)]` `NqDtypeClass` (Numeric, Integer, SignedInteger, UnsignedInteger, Float) and `nq_expr_selector` (names, dtype codes, class bit set, wildcard, excluded names)
- [x] 1.2 Add `nq_expr_name_affix` (suffix or prefix)
- [x] 1.3 Mirror both in `ffi.nim`; verify that `cargo build --release` passes

## 2. Nim API

- [x] 2.1 Add the `Selector` value type, its converter to `Expr`, and `$`
- [x] 2.2 Add `col` for Nim types and typeclasses (macro), several types, and several names; add `all()`
- [x] 2.3 Add `exclude(names)` on `Selector`
- [x] 2.4 Add `name.suffix` and `name.prefix`
- [x] 2.5 Write `tests/test_selectors.nim`: each typeclass and concrete type, `col(float, int)`, `col("a", "b")`, `all()`, regex, `exclude`, use in `select`/`withColumns`/`agg`, two aggregations with suffixes, and `col(seq[int])` not compiling; add it to `nanuq.nimble` and `.gitignore`

## 3. Docs and integration

- [x] 3.1 List the selectors in the README "What is there"; verify that `nimble test` and `nimble example` pass
- [x] 3.2 Check that CI is green on the PR

## Workflow follow-up

- Archive the change (`/opsx:archive`), and add CHANGELOG lines with the PR number.
