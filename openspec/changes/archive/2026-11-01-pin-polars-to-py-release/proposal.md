# Proposal

## Why

Nanuq pinned the newest Polars crate on crates.io (0.55.2). The Rust crates are
released by hand every few months, and 0.55.2 matches py-polars 1.43, while the book
and the explainers compare against py-polars 2.1.0, about 940 commits later. The 0.5
and 0.6 ports kept finding the drift: SQL table functions with named options fail,
`hash` and `sample` give other values, SQL `COUNT(*)` has another type, Decimal `mod`
is missing. The research thread "Understand how Polars and py-polars versions align"
(`/mnt/project-files/polars-versions/report.md`) recommends pinning the git tag of the
py-polars release instead. Pietro asked for it in the 0.6 release (2026-11-01).

It is the twelfth change of the 0.6 release.

## What Changes

- `src/rust/Cargo.toml`: `polars`, `polars-core`, `polars-plan`, `polars-utils` and
  `polars-arrow` come from `git = "https://github.com/pola-rs/polars", tag = "py-2.1.0"`
  (commit 7f902bd), with the workspace's `[patch.crates-io]` entries copied (a git
  dependency does not inherit them).
- Release builds (`release-lib.yml`) use the tag's toolchain, `nightly-2026-09-01`.
- The wrapper adapts to the Polars API changes between 0.55 and py-2.1.0.
- **Breaking**, as in Polars 2.0: `profile` and `cat.getCategories` are gone (both are
  compile-time errors that say what to use instead); `hash(seed)` uses one seed.
- Behavior that follows Polars 2.0: CSV read without a header names its columns
  `column_0`, `column_1`, ... (was `column_1`, ...); `topK`/`bottomK` on expressions and
  series no longer happen to come out sorted (as documented); a left join without
  `maintainOrder` no longer keeps the left order (the join example now passes
  `maintainOrder = Left`); `unpivot` emits rows in row-major order.
- BACKLOG "Track the Rust Polars that py-polars ships" is done.

## Capabilities

### Modified Capabilities
- `native-bridge`: which Polars the crate builds on.
- `streaming`: `profile` removed.
- `categoricals`: `cat.getCategories` removed.

## Differences from Polars

- None added: the point is to remove the version drift. Nanuq now matches py-polars
  2.1.0 (same commit); the book and explainers keep py-polars 2.1.0 as their oracle.

## Impact

- `src/rust/Cargo.toml`, `Cargo.lock`, `src/rust/src/lib.rs` (API updates),
  `.github/workflows/release-lib.yml`; spec example outputs that changed with Polars.
- A cold build fetches the Polars repository by git (CI caches `target/` and the cargo
  home as before).
