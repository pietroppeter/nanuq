# Spec Delta

## MODIFIED Requirements

### Requirement: Errors and panics never cross the boundary
Every FFI function SHALL catch Polars errors and Rust panics, signal failure with a NULL
(or false / -1) return, and make the message available through `nq_last_error` and its kind through
`nq_last_error_kind`.

#### Scenario: Polars error
- **WHEN** an operation fails in Polars (e.g. a missing column)
- **THEN** the function returns NULL and `nq_last_error` returns the Polars message

#### Scenario: Rust panic
- **WHEN** Polars panics inside an FFI call
- **THEN** the panic is caught, the call returns NULL, and no unwinding reaches Nim

#### Scenario: Error kind
- **WHEN** an operation fails with a Polars `ColumnNotFound` error, possibly wrapped in context
- **THEN** `nq_last_error_kind` returns `ColumnNotFound`

### Requirement: Nim declarations mirror the C ABI
`src/nanuq/ffi.nim` SHALL declare every exported function with matching signatures, and
the enums `NqBinOp`, `NqUnary`, `NqDtype`, `NqDtypeClass`, `NqJoinType`,
`NqJoinValidation`, `NqMaintainOrderJoin`, `NqConcat`, `NqUniqueKeepStrategy`,
`NqClosedInterval`, `NqQuantileMethod`, `NqFillNullStrategy`, `NqRoundMode`,
`NqQuoteStyle`, `NqRankMethod` and `NqErrorKind` SHALL keep the same order as in Rust. `NqDtype` SHALL also keep the order
of `DataTypeKind`, and the option enums the order of their Nim API enums.

#### Scenario: ABI change
- **WHEN** a function is added or changed in `rust/src/lib.rs`
- **THEN** `src/nanuq/ffi.nim` is updated in the same change
