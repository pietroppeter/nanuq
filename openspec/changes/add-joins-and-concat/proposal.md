# Proposal

## Why

Nanuq can query one table, but real analyses combine several: measurements with a
lookup table, this month's file with last month's, a set of keys with the rows that
match them. Joins and concatenation are the most used Polars verbs that Nanuq still
lacks, and the 0.2 plan puts them right after data types (casting key columns to a
common type is the usual fix when a join refuses mismatched keys).

This change takes up the BACKLOG.md entry "Joins" (API) and adds concatenation, which
has no entry. It is the second change of the 0.2 release (see the Polars coverage map,
area "Joins and concatenation").

## What Changes

- New `join` on LazyFrame and DataFrame, with Polars' join types: inner, left, right,
  full, semi, anti and cross.
  - Keys by name (`on = ["station"]`), or different names on each side
    (`leftOn = ["id"], rightOn = ["station_id"]`), as strings or expressions.
  - `how` takes a `JoinType` value, written like Python's string: `how = left`.
  - Options as named parameters with Polars' defaults: `suffix = "_right"`,
    `validate` (`JoinValidation`: many-to-many by default), `nullsEqual = false`,
    `coalesce` (`none(bool)` = Polars' per-join-type default), and `maintainOrder`
    (`JoinOrder`, Polars' default: no order guaranteed).
  - A cross join takes no keys: `a.join(b, how = cross)`.
- New `concat` of several LazyFrames or DataFrames, with `how` a `ConcatMethod`:
  `vertical` (default), `verticalRelaxed`, `horizontal`, `diagonal`,
  `diagonalRelaxed`.
- Polars features `semi_anti_join`, `cross_join` and `diagonal_concat` are compiled
  in. The ABI stays `0.2.0-dev` (released as `lib-v0.2.0` with the rest of 0.2).

## Capabilities

### New Capabilities
- `combining-frames`: joins and concatenation of DataFrames and LazyFrames.

### Modified Capabilities
- `native-bridge`: the enums that must keep the same order in Rust and `ffi.nim` now
  include the join and concat enums.

## Differences from Polars

Expected differences from Polars' Rust and Python APIs:

- **Enums instead of strings.** Python's `how="left"`, `validate="1:m"`,
  `maintain_order="left"` and `pl.concat(how="diagonal")` become Nim enums. Join types
  and concat methods have Polars' names as enum values (`how = left`,
  `how = diagonal`); Nim resolves them from the parameter type. A local variable
  called `left` shadows the value; write `JoinType.left` then.
- **Validation names.** Python's `"m:m"`, `"m:1"`, `"1:m"`, `"1:1"` become
  `manyToMany`, `manyToOne`, `oneToMany`, `oneToOne`, as in Rust's `JoinValidation`.
- **Order names.** Python's `maintain_order` values `"none"`, `"left"`, `"right"`,
  `"left_right"`, `"right_left"` become `JoinOrder` values `noOrder`, `leftOrder`,
  `rightOrder`, `leftRightOrder`, `rightLeftOrder`, so they don't clash with the
  join types `left` and `right`.
- **`coalesce`** is an `Option[bool]` (Python's `None`, `True`, `False`).
- **No keyword-only checks.** Python rejects `on` together with `left_on`; Nim
  overloads make the two forms separate procs, so mixing them doesn't compile.
- **Not in this change:** `join_asof`, `join_where`, `merge_sorted`, `update`,
  `vstack`/`hstack`/`extend`, `pl.concat(how="align")`, Series concatenation, and
  `concat`'s `rechunk`/`parallel` flags. They stay in the coverage map for later
  releases.
- **Names** follow Polars in camelCase: `left_on` → `leftOn`, `right_on` → `rightOn`,
  `nulls_equal` → `nullsEqual`, `maintain_order` → `maintainOrder`,
  `vertical_relaxed` → `verticalRelaxed`, `diagonal_relaxed` → `diagonalRelaxed`.

## Impact

- `src/rust/src/lib.rs`: `#[repr(C)]` enums `NqJoinType`, `NqJoinValidation`,
  `NqJoinOrder`, `NqConcat`; `nq_lf_join` and `nq_lf_concat`. `Cargo.toml` adds the
  three Polars features. The Rust library is rebuilt in CI (the first run takes about
  10 minutes).
- `src/nanuq/ffi.nim`, `src/nanuq.nim`: the matching declarations, the enums and the
  procs.
- `tests/test_combining.nim`: every join type, key forms, options, and every concat
  method.
- `README.md`: the API list mentions `join` and `concat`.
