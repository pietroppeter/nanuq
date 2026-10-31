# Tasks

## 1. Bridge

- [ ] 1.1 Add Polars features `semi_anti_join`, `cross_join` and `diagonal_concat` to `src/rust/Cargo.toml` (version stays `0.2.0-dev`); verify `cargo build --release` passes
- [ ] 1.2 Add `#[repr(C)]` `NqJoinType`, `NqJoinValidation`, `NqJoinOrder` and `nq_lf_join` (keys checks for cross and non-cross joins); mirror them in `ffi.nim`
- [ ] 1.3 Add `NqConcat` and `nq_lf_concat` (vertical, relaxed, horizontal, diagonal); mirror them in `ffi.nim`; verify `cargo build --release` passes

## 2. Nim API

- [ ] 2.1 Add `JoinType`, `JoinValidation`, `JoinOrder`, `ConcatMethod`, in the same order as the Rust enums
- [ ] 2.2 Add `join` on LazyFrame and DataFrame for `on` and `leftOn`/`rightOn` (strings and expressions) and the keyless cross join, with all options; verify every join type, both key forms, suffix, validation failure, `nullsEqual`, `coalesce` and `maintainOrder`
- [ ] 2.3 Add `concat` for LazyFrames and DataFrames; verify every method, the strict vertical failure and the empty list error

## 3. Docs and integration

- [ ] 3.1 Update README "What is there" with `join` and `concat` (and that join order is not guaranteed without `maintainOrder`); verify `nimble test` and `nimble example` pass
- [ ] 3.2 Check that CI is green on the PR, including the Rust rebuild

## Workflow follow-up

- Archive the change (`/opsx:archive`): remove the "Joins" entry from BACKLOG.md, and add a CHANGELOG line with the PR number.
