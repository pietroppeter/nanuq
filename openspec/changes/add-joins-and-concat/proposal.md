# Proposal

## Why

Nanuq can query one table, but real analyses combine several: measurements with a
lookup table, this month's file with last month's, a set of keys with the rows that
match them. Joins and concatenation are the most used Polars verbs that Nanuq still
lacks, and the 0.2 plan puts them right after data types (casting key columns to a
common type is the usual fix when a join refuses mismatched keys).

This change takes up the BACKLOG.md entry "Joins" (API) and adds concatenation, which
has no entry. Joins are the first verbs with many option values, so the change also
settles, for all of Nanuq, how option values are spelled in Nim (decided by Pietro on
2026-10-31 after a design note comparing strings, prefixed enums, pure enums and one
proc per variant). It is the second change of the 0.2 release (see the Polars coverage map,
area "Joins and concatenation").

## What Changes

- New `join` on LazyFrame and DataFrame, with Polars' join types: inner, left, right,
  full, semi, anti and cross.
  - Keys by name (`on = ["station"]`), or different names on each side
    (`leftOn = ["id"], rightOn = ["station_id"]`), as strings or expressions.
  - `how` takes a `JoinType` value: `how = Left`.
  - Options as named parameters with Polars' defaults: `suffix = "_right"`,
    `validate` (`JoinValidation`, default `ManyToMany`), `nullsEqual = false`,
    `coalesce` (`none(bool)` = Polars' per-join-type default), and `maintainOrder`
    (`MaintainOrderJoin`, default `None`: no order guaranteed).
  - A cross join takes no keys: `a.join(b, how = Cross)`.
- New `concat` of several LazyFrames or DataFrames, with `how` a `ConcatMethod`:
  `Vertical` (default), `VerticalRelaxed`, `Horizontal`, `Diagonal`,
  `DiagonalRelaxed`.
- **API convention for option values (all of Nanuq):** a closed set of option values
  is a pure enum (`{.pure.}`) with the Rust Polars type name and its PascalCase variant
  names, e.g. `JoinType.Left`, written bare (`how = Left`) where the type is known.
  The convention is recorded as a new spec, in `openspec/config.yaml` (so every later
  proposal follows it) and in the README.
- **BREAKING:** `DataTypeKind` follows the convention: `dkInt64` becomes
  `DataTypeKind.Int64`, `dkOther` becomes `DataTypeKind.Other`. The `DataType`
  constants (`Int64`, `String`, ...) are unchanged and still what users normally write.
- Polars features `semi_anti_join`, `cross_join` and `diagonal_concat` are compiled
  in. The ABI stays `0.2.0-dev` (released as `lib-v0.2.0` with the rest of 0.2).

## Capabilities

### New Capabilities
- `combining-frames`: joins and concatenation of DataFrames and LazyFrames.
- `api-conventions`: naming rules that apply across the Nim API, starting with how
  option values are spelled.

### Modified Capabilities
- `data-types`: `DataTypeKind` values become pure PascalCase (`DataTypeKind.Other`).
- `native-bridge`: the enums that must keep the same order in Rust and `ffi.nim` now
  include the join and concat enums.

## Differences from Polars

Expected differences from Polars' Rust and Python APIs:

- **Enums instead of strings.** Python's `how="left"`, `validate="1:m"`,
  `maintain_order="left_right"` and `pl.concat(how="diagonal")` become pure enums with
  Rust's names: `JoinType.Left`, `JoinValidation.OneToMany`,
  `MaintainOrderJoin.LeftRight`, and `ConcatMethod.Diagonal`. In a typed context the
  bare value works (`how = Left`); elsewhere it must be qualified, as in Rust. Two
  enums may share a value name (`JoinType.Left`, `MaintainOrderJoin.Left`), as in Rust.
- **`ConcatMethod` is Nanuq's.** Rust has no single enum for concat (it has separate
  functions and `UnionArgs` flags); the name and the values follow Python's `how`
  strings in PascalCase.
- **`coalesce`** is an `Option[bool]` (Python's `None`, `True`, `False`).
- **No keyword-only checks.** Python rejects `on` together with `left_on`; Nim
  overloads make the two forms separate procs, so mixing them doesn't compile.
- **Not in this change:** `join_asof`, `join_where`, `merge_sorted`, `update`,
  `vstack`/`hstack`/`extend`, `pl.concat(how="align")`, Series concatenation, and
  `concat`'s `rechunk`/`parallel` flags. They stay in the coverage map for later
  releases.
- **Names** follow Polars in camelCase: `left_on` → `leftOn`, `right_on` → `rightOn`,
  `nulls_equal` → `nullsEqual`, `maintain_order` → `maintainOrder`.

## Impact

- `src/rust/src/lib.rs`: `#[repr(C)]` enums `NqJoinType`, `NqJoinValidation`,
  `NqMaintainOrderJoin`, `NqConcat`; `nq_lf_join` and `nq_lf_concat`. `Cargo.toml` adds the
  three Polars features. The Rust library is rebuilt in CI (the first run takes about
  10 minutes).
- `src/nanuq/ffi.nim`, `src/nanuq.nim`: the matching declarations, the enums and the
  procs; `DataTypeKind` becomes pure (its uses in `src/nanuq.nim` and the tests are
  updated).
- `openspec/config.yaml`: a proposal rule pointing at the `api-conventions` spec.
- `tests/test_combining.nim`: every join type, key forms, options, and every concat
  method.
- `README.md`: the API list mentions `join` and `concat`, and a short "Conventions"
  section states the option-value rule.
