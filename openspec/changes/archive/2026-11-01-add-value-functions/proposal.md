# Proposal

## Why

A whole family of Polars expressions works on the values of one column as a set or a
sequence: sort it, take the top five, find duplicates, recode values, bin numbers into
categories, count how often each value occurs. Nanuq 0.3 has them only at frame level
(`sort`, `unique`, `head`), so they can't be used inside `agg` or `over`, and recoding or
binning needs a `when` chain. The book ports hit `top_k`, `value_counts`, `is_unique`,
`replace`, `cut` and `sort_by` across the O'Reilly chapters 8 and 13 and the user guide.

It is the fourth change of the 0.4 release.

## What Changes

- **Order**: `Expr.sort(descending, nullsLast)`, `argSort`, `sortBy(by, descending)`,
  `reverse`.
- **Picking values**: `Expr.head(n)`, `tail(n)`, `slice(offset, length)`, `gather(indices)`,
  `gatherEvery(n, offset)`, `topK(k)`, `bottomK(k)`, `topKBy(by, k, reverse)`,
  `bottomKBy`, `indexOf(value)`, `searchSorted(element, side)` with a
  `SearchSortedSide` pure enum.
- **Distinct values**: `Expr.unique(maintainOrder)`, `argUnique`, `isUnique`,
  `isDuplicated`, `isFirstDistinct`, `isLastDistinct`, `uniqueCounts`, `approxNUnique`.
- **Recoding and binning**: `replace(old, new)` and `replace({old: new, ...})`,
  `replaceStrict` with `default`, `cut(breaks, labels, leftClosed)`,
  `qcut(quantiles or n, labels, leftClosed, allowDuplicates)`.
- **Counting**: `valueCounts(column, sort, normalize, name)` on DataFrame and
  LazyFrame.

## Capabilities

### New Capabilities
- `value-functions`: order, picking, distinct values, recoding, binning and counting.

## Differences from Polars

- `valueCounts` is a frame method taking the column (Python: `Series.value_counts`,
  or `Expr.value_counts`, which returns a Struct; Struct columns come in 0.5).
- `replace` takes a Nim mapping literal `{"a": "x"}` (an array of pairs) where Python
  takes a dict; `replaceStrict` has no `return_dtype` (cast the result instead).
- `cut` and `qcut` have no `include_breaks` (it returns a Struct). They return an Enum,
  as in Python Polars 2, which deprecates `cut` in favour of `bin_intervals`; Nanuq keeps
  Rust's name `cut`.
- `topKBy` takes `by` before `k` so that `k` can keep its default; Python is
  `top_k_by(by, k=5)` too, Rust is `top_k_by(k, by, reverse)`.
- `Expr.head` and `tail` default to 10 values as in Python (frames default to 5).

## Impact

- `src/rust/src/lib.rs`: `NqUnary` and `NqBinaryFn` grow, `nq_expr_sort`,
  `nq_expr_sort_by`, `nq_expr_top_k_by`, `nq_expr_slice`, `nq_expr_gather_every`,
  `nq_expr_replace`, `nq_expr_cut`, `nq_lf_value_counts`; `src/nanuq/ffi.nim`,
  `src/nanuq.nim`.
- New `tests/test_values.nim`.
