# Spec Delta

## MODIFIED Requirements

### Requirement: Nim declarations mirror the C ABI
`src/nanuq/ffi.nim` SHALL declare every exported function with matching signatures, and
the enums `NqBinOp`, `NqUnary`, `NqDtype`, `NqDtypeClass`, `NqJoinType`,
`NqJoinValidation`, `NqMaintainOrderJoin`, `NqConcat`, `NqUniqueKeepStrategy`,
`NqClosedInterval`, `NqQuantileMethod`, `NqFillNullStrategy`, `NqRoundMode`,
`NqQuoteStyle` and `NqRankMethod` SHALL keep the same order as in Rust. `NqDtype` SHALL also keep the order
of `DataTypeKind`, and the option enums the order of their Nim API enums.

#### Scenario: ABI change
- **WHEN** a function is added or changed in `rust/src/lib.rs`
- **THEN** `src/nanuq/ffi.nim` is updated in the same change
