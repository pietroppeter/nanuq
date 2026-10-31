# Tasks

## 1. Bridge

- [ ] 1.1 Add Polars features `semi_anti_join`, `cross_join` and `diagonal_concat` to `src/rust/Cargo.toml` (version stays `0.2.0-dev`); verify `cargo build --release` passes
- [ ] 1.2 Add `#[repr(C)]` `NqJoinType`, `NqJoinValidation`, `NqMaintainOrderJoin` and `nq_lf_join` (keys checks for cross and non-cross joins); mirror them in `ffi.nim`
- [ ] 1.3 Add `NqConcat` and `nq_lf_concat` (vertical, relaxed, horizontal, diagonal); mirror them in `ffi.nim`; verify `cargo build --release` passes

## 2. Nim API

- [ ] 2.1 Make `DataTypeKind` a pure enum with PascalCase values (`DataTypeKind.Int64`, `DataTypeKind.Other`); update `src/nanuq.nim`, `datamancer.nim` and tests; verify `nimble test` passes and a bare `Int64` still means the `DataType` constant
- [ ] 2.2 Add the pure enums `JoinType`, `JoinValidation`, `MaintainOrderJoin`, `ConcatMethod`, in the same order as the Rust enums
- [ ] 2.3 Add `join` on LazyFrame and DataFrame for `on` and `leftOn`/`rightOn` (strings and expressions) and the keyless cross join, with all options; verify every join type, both key forms, suffix, validation failure, `nullsEqual`, `coalesce`, `maintainOrder`, and that `how = Left, maintainOrder = Left` compiles
- [ ] 2.4 Add `concat` for LazyFrames and DataFrames; verify every method, the strict vertical failure and the empty list error

## 3. Conventions, docs and integration

- [ ] 3.1 Add a proposal rule to `openspec/config.yaml` that option values follow the `api-conventions` spec
- [ ] 3.2 Add a "Conventions" section to the README (Polars names in camelCase, pure enums with Rust names for option values, qualify outside typed contexts) and list `join` and `concat` in "What is there" (with the note that join order is not guaranteed without `maintainOrder`); verify `nimble test` and `nimble example` pass
- [ ] 3.3 Check that CI is green on the PR, including the Rust rebuild

## Workflow follow-up

- Archive the change (`/opsx:archive`): remove the "Joins" entry from BACKLOG.md, and add CHANGELOG lines with the PR number (Added: joins, concat, API conventions; Changed: `DataTypeKind` values are pure PascalCase).
