# Tasks

## 1. Bridge

- [ ] 1.1 Add the Polars features `is_in`, `is_between` and `abs` to `src/rust/Cargo.toml`
- [ ] 1.2 Add `NqBinOp` values `Mod`, `FloorDiv` and `Pow`, and `NqUnary` values `Abs`, `Median`, `Len` and `Neg`
- [ ] 1.3 Add `nq_expr_when_then`, `nq_expr_is_in`, `nq_expr_lit_series`, `nq_expr_is_between` (`NqClosedInterval`), `nq_expr_quantile` (`NqQuantileMethod`), `nq_expr_var_std`, `nq_expr_fill_null_strategy` (`NqFillNullStrategy`) and `nq_expr_over`
- [ ] 1.4 Mirror everything in `ffi.nim`; verify that `cargo build --release` passes

## 2. Nim API

- [ ] 2.1 Add the conditional chain (`` `when` ``, `then`, `when`, `otherwise`, and a converter to `Expr`) and the `choose` macro
- [ ] 2.2 Add `isIn` (values and expression) and `isBetween` with `ClosedInterval`
- [ ] 2.3 Add `mod`, `div`, `^`/`pow`, `abs` and unary `-`
- [ ] 2.4 Add `median`, `var`, `std(ddof)`, `quantile` with `QuantileMethod`, and `len`
- [ ] 2.5 Add `fillNull(strategy, limit)` with `FillNullStrategy`, plus `forwardFill` and `backwardFill`
- [ ] 2.6 Add `over` (name, names, expressions)
- [ ] 2.7 Write `tests/test_expressions.nim`: every function and option, a chain without `otherwise`, string literals in branches, the macro giving the same `$expr` as the chain, a macro misuse failing to compile, floor semantics of `mod`/`div`, and forward fill with and without `over`; add it to `nanuq.nimble` and `.gitignore`

## 3. Docs and integration

- [ ] 3.1 List the new expressions in the README, and note in "Conventions" that operators keep Polars' semantics; verify that `nimble test` and `nimble example` pass
- [ ] 3.2 Check that CI is green on the PR, including the Rust rebuild

## Workflow follow-up

- Archive the change (`/opsx:archive`). Narrow the BACKLOG "More expressions" entry to string functions, and add CHANGELOG lines with the PR number.
