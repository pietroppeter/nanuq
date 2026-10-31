# Tasks

## 1. Bridge

- [ ] 1.1 Add the Polars feature `random` to `src/rust/Cargo.toml`
- [ ] 1.2 Add `nq_lf_drop`, `nq_lf_rename`, `nq_lf_slice`, `nq_lf_reverse` and `nq_lf_with_row_index`
- [ ] 1.3 Add `NqUniqueKeepStrategy` and `nq_lf_unique` (stable when `maintain_order`)
- [ ] 1.4 Replace `nq_lf_sort` with `nq_lf_sort_by` (expressions, bool lists, `maintain_order`)
- [ ] 1.5 Add `nq_df_sample` (n or fraction, replacement, shuffle, optional seed)
- [ ] 1.6 Mirror everything in `ffi.nim`; verify that `cargo build --release` passes

## 2. Nim API

- [ ] 2.1 Add `drop`, `rename`, `head` (LazyFrame), `tail`, `slice`, `reverse` and `withRowIndex` on LazyFrame, with DataFrame shortcuts
- [ ] 2.2 Add the pure enum `UniqueKeepStrategy` and `unique`
- [ ] 2.3 Add multi-key `sort` (names and expressions), and `nullsLast` and `maintainOrder` on the one-column `sort`
- [ ] 2.4 Add `sample` on DataFrame (n and fraction overloads)
- [ ] 2.5 Write `tests/test_verbs.nim` covering each verb, strict failures, negative offsets, every keep strategy, sort broadcasting and the length mismatch error, and seeded samples that repeat; add it to `nanuq.nimble` and `.gitignore`

## 3. Docs and integration

- [ ] 3.1 List the new verbs in the README "What is there"; verify that `nimble test` and `nimble example` pass
- [ ] 3.2 Check that CI is green on the PR, including the Rust rebuild

## Workflow follow-up

- Archive the change (`/opsx:archive`). Add CHANGELOG lines with the PR number (Added: frame verbs, multi-key sort, `sample`).
