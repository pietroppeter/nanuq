# Tasks

## 1. Bridge

- [ ] 1.1 Move `src/rust/Cargo.toml` to version `0.2.0-dev` and add Polars features `dtype-i8`, `dtype-i16`, `dtype-u8`, `dtype-u16`; verify `cargo build --release` passes and `ffi.nim` falls back to the local build
- [ ] 1.2 Add `#[repr(C)] NqDtype` with conversions to and from Polars `DataType`, and `nq_df_column_dtype_kind`; mirror both in `ffi.nim`
- [ ] 1.3 Add `nq_lf_collect_schema` (empty DataFrame with the resolved schema), `nq_expr_cast` and `nq_lf_cast` (strict flag); mirror them in `ffi.nim`; verify `cargo build --release` passes

## 2. Nim API

- [ ] 2.1 Add `DataTypeKind`, `DataType`, the constants, `==`, `$` and the predicates; verify with unit tests that need no DataFrame
- [ ] 2.2 Change `dtype(df, col)` to return `DataType` (name lookup for `dkOther`); update `datamancer.nim`, the HTML table and the tests that compare dtype strings; verify `nimble test` passes
- [ ] 2.3 Add `Schema`, `schema(df)`, `dtypes(df)` and `collectSchema(lf)`; verify column order and that a lazy schema does not execute the query
- [ ] 2.4 Add `dataType(T)` for the supported Nim types; verify the mapping, and with a compile-time check that an unsupported type does not compile
- [ ] 2.5 Add `cast` on Expr, and on LazyFrame and DataFrame for all columns (Nim type or `DataType`) and for named columns (`DataType`); verify narrowing, a Nim-type target, strict failure, non-strict nulls and the `dkOther` error

## 3. Docs and integration

- [ ] 3.1 Update README "What is there" with `DataType`, `schema` and `cast`; verify `nimble example` passes and the dev-log post output is unchanged
- [ ] 3.2 Check that CI is green on the PR, including the one-off Rust rebuild

## Workflow follow-up

- Archive the change (`/opsx:archive`): remove casting from the "More expressions" entry in BACKLOG.md, and add a CHANGELOG line with the PR number that calls out the breaking `dtype` change.
