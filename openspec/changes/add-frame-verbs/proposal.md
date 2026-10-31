# Proposal

## Why

Nanuq can filter, select and sort by one column. But a lot of everyday table work happens
between those steps: dropping or renaming columns, looking at the last rows or a
window of them, taking a random sample, removing duplicate rows, numbering rows, and
sorting by several keys with nulls at the end. Polars has a small, stable verb for each
of these. Without them, Nanuq users have to write `select` lists by hand or go back
through Nim seqs.

This is the third change of the 0.2 release (see the Polars coverage map, area "Frame
verbs"). It has no BACKLOG.md entry.

## What Changes

- New verbs on LazyFrame, with eager DataFrame shortcuts:
  - `drop("a", "b", strict = true)` removes columns.
  - `rename({"old": "new"}, strict = true)` renames columns.
  - `head(n = 5)` (LazyFrame; DataFrame already has it) and `tail(n = 5)` keep the first
    or last rows.
  - `slice(offset)` and `slice(offset, length)` keep a window of rows. A negative offset
    counts from the end.
  - `unique("a", keep = First, maintainOrder = false)` drops duplicate rows, judged on
    all columns or on the named ones. `keep` is a `UniqueKeepStrategy`: `Any` (default),
    `First`, `Last` or `None`.
  - `reverse()` reverses the row order.
  - `withRowIndex(name = "index", offset = 0)` adds a row number column first.
- Sorting by several keys: `sort(["species", "mass"], descending = [false, true],
  nullsLast = [true], maintainOrder = false)`, by column names or expressions. A single
  value in `descending` or `nullsLast` applies to every key. The one-column
  `sort(by, descending)` gains `nullsLast` and `maintainOrder`.
- `sample` on DataFrame: `sample(n, withReplacement = false, shuffle = false,
  seed = none(int))`, and `sample(fraction = 0.1, ...)`.
- New pure enum `UniqueKeepStrategy`, following the `api-conventions` spec.
- Polars feature `random` is compiled in (for `sample`). The ABI stays `0.2.0-dev`.

## Capabilities

### New Capabilities
- `frame-verbs`: column and row verbs on DataFrames and LazyFrames (drop, rename,
  head/tail/slice, unique, reverse, withRowIndex, sample) and sorting by several keys.

### Modified Capabilities
- `native-bridge`: `NqUniqueKeepStrategy` joins the enums that keep the same order in
  Rust and `ffi.nim`.

## Differences from Polars

Expected differences from Polars' Rust and Python APIs:

- **`keep` is an enum.** Python's `keep="first"` becomes `keep = First` (pure enum
  `UniqueKeepStrategy`, Rust's type and names).
- **`descending` and `nullsLast` in multi-key sort are lists.** Python takes a bool or a
  list. Nim takes `openArray[bool]`: one value applies to all keys, as in Rust's
  `SortMultipleOptions`. Empty (the default) means all false. The one-column `sort` keeps
  plain bools.
- **`slice` without a length** is a separate overload instead of Python's
  `length=None`.
- **`sample` is DataFrame only**, as in Python (LazyFrame has no `sample`). `n` and
  `fraction` are two overloads, chosen by the argument name (`fraction = 0.1`) or type,
  and one of them is required (Python defaults to one row when both are missing).
  `seed` is an `Option[int]`.
- **`rename` takes pairs only.** Python also accepts a function from old to new name.
  That form is left for later.
- **`unique`'s subset** is a list of names (`varargs`), like `dropNulls`. Selectors and
  expressions come with the column selectors change.
- **Not in this change:** `drop` with selectors, `gather_every`, `shift`, `top_k`/`bottom_k`,
  `clear`, `first`/`last` on frames, `with_row_count` (deprecated in Python), and sort's
  `multithreaded` flag. They stay in the coverage map.
- **Names** follow Polars in camelCase: `with_row_index` → `withRowIndex`, `nulls_last`
  → `nullsLast`, `maintain_order` → `maintainOrder`, `with_replacement` →
  `withReplacement`.

## Impact

- `src/rust/src/lib.rs`: `nq_lf_drop`, `nq_lf_rename`, `nq_lf_slice`, `nq_lf_unique`,
  `nq_lf_reverse`, `nq_lf_with_row_index`, `nq_df_sample`, and `nq_lf_sort_by` replacing
  `nq_lf_sort`. New `#[repr(C)]` enum `NqUniqueKeepStrategy`. `Cargo.toml` adds the
  `random` feature. CI rebuilds the Rust library.
- `src/nanuq/ffi.nim` and `src/nanuq.nim` get the matching declarations, the enum and
  the procs.
- `tests/test_verbs.nim` covers each verb and its options.
- `README.md` lists the new verbs in "What is there".
