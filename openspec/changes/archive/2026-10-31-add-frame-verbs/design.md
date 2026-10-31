# Design

## Context

Lazy verbs cross the ABI as functions that borrow a `LazyFrame` and return a new one.
Lists of names go across as a pointer and a length. Enums cross as `#[repr(C)]` integers
mirrored in `ffi.nim`. DataFrame verbs are eager shortcuts: `df.lazy.<verb>.collect`.

Polars 0.55 has:
- `LazyFrame::drop(Selector)`, `rename(existing, new, strict)`, `slice(offset: i64, len:
  IdxSize)`, `tail(n)` and `limit(n)`.
- `unique_generic(Option<Vec<Expr>>, UniqueKeepStrategy)` and its `unique_stable`
  variant, `reverse()`, `with_row_index(name, Option<IdxSize>)`, and
  `sort_by_exprs(exprs, SortMultipleOptions)`.
- `DataFrame::sample_n_literal` and `sample_frac`, behind the `random` feature.

## Goals / Non-Goals

**Goals:**
- Each verb Python Polars has on DataFrame and LazyFrame in this list, with the same
  defaults.
- One Rust function per verb, carrying all of its options.

**Non-Goals:**
- Selectors (`cs.numeric()`, regex) as verb arguments. That is the column selectors
  change, which can widen `drop` and `unique` later without breaking these forms.
- A lazy `sample`. Python has none. It would need a select over every column with
  `sample_n`.

## Decisions

### `drop` and `strict`
`nq_lf_drop(lf, names, n, strict)` builds `by_name(names, strict)`. With
`strict = true`, a missing column raises `NanuqError` when the query runs, as in Python.

### `rename` keeps both lists
`nq_lf_rename(lf, existing, new, n, strict)` maps onto `LazyFrame::rename`. Nim takes
`openArray[(string, string)]`, so `df.rename({"a": "x"})` reads like `cast({"a": Int32})`.

### `slice`, `head`, `tail`
`nq_lf_slice(lf, offset: i64, len: u32)`. When there is no length, Nim passes
`high(uint32)`, as Python does for `length=None`. LazyFrame `head(n)` is `limit(n)`.
`tail(n)` is `slice(-n, n)`, done in Nim with no extra ABI function.

### `unique`
`nq_lf_unique(lf, names, n, keep: NqUniqueKeepStrategy, maintain_order)` calls
`unique_stable_generic` when `maintain_order`, and `unique_generic` otherwise. An empty
subset means all columns.

### One sort function
`nq_lf_sort_by(lf, exprs, n, descending: *const bool, n_desc, nulls_last: *const bool,
n_nulls, maintain_order)` replaces `nq_lf_sort`. Nim builds `col(name)` for string keys.
Rust passes the bool lists to `SortMultipleOptions` as they are: an empty list becomes
`[false]`, and one value broadcasts. A list whose length is neither 1 nor the number of
keys raises `NanuqError`.
- *Why:* one ABI function covers single and multiple keys and both key forms. The
  one-column `sort(by: string, ...)` in Nim becomes a thin wrapper.

### `sample` on DataFrame
`nq_df_sample(df, n: usize, fraction: f64, by_fraction: bool, with_replacement, shuffle,
has_seed, seed: u64)`. Nim overloads `sample(df, n: int, ...)` and
`sample(df, fraction: float, ...)`. `seed = none(int)` means a random seed. A negative
seed raises `ValueError` in Nim before the call.
- *Alternative:* `n = -1` and `fraction = NaN` as "unset" in one proc. Overloads read
  better and give a compile error when neither is passed.

### `withRowIndex`
`nq_lf_with_row_index(lf, name, offset: u32)`. A negative offset raises `ValueError` in
Nim.

## Risks / Trade-offs

- The `random` feature adds the `rand` crates to the build. That costs seconds against
  the Polars build.
- Replacing `nq_lf_sort` changes the ABI. That is fine within `0.2.0-dev`.
