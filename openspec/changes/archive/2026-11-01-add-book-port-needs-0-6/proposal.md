# Proposal

## Why

Porting the chapters 0.5 already unlocks (O'Reilly ch5, ch9, ch13; Packt ch4, ch5; the
user guide's aggregation pages), the 0.6 book thread found gaps the planning map could
not see, because the names exist on expressions but not on frames or group-bys: frame
aggregations (`df.sum()`), group-by shortcuts (`group_by(...).max()`), iterating over
groups, `df.fill_nan`, and `pl.select` without a frame.

It is the tenth change of the 0.6 release.

## What Changes

- Frame aggregations on DataFrame and LazyFrame: `sum`, `mean`, `median`, `product`,
  `min`, `max`, `std(ddof)`, `var(ddof)`, `quantile(q, interpolation)`, `nUnique`,
  `count`, `nullCount()`. Columns the aggregation does not apply to give null, as in
  Python.
- Group-by shortcuts on GroupBy and LazyGroupBy: `len(name)`, `count`, `head(n)`,
  `tail(n)`, `first`, `last`, `sum`, `mean`, `median`, `min`, `max`, `nUnique`,
  `quantile(q)`, `all` (lists).
- `for key, part in df.groupBy(...)`: the groups in order of appearance.
- `fillNan(value | nil)` on DataFrame and LazyFrame (float columns).
- `select(exprs...)` without a frame (Python `pl.select`).
- Round 2 from the book (O'Reilly ch9, Packt ch4, user guide data types):
  - operators on selectors (`all() > 0` keeps each column's name, not "literal");
  - comparisons with a value on the left are mirrored (`0 < col("a")` is
    `col("a") > 0`, named `a`), as Python's reflected comparisons do;
  - `over("a", "b")` with several names; `concatStr([all()], sep)` with selectors;
  - `describe` prints datetimes and the mean of dates as Python's `str(datetime)`
    does (`1986-09-04 00:00:00`, no `.000000`).
  - `xor` came in add-frame-utilities-0-6.

## Capabilities

### Modified Capabilities
- `frame-verbs`: frame aggregations, group-by shortcuts, group iteration, frame `fillNan`, `select` without a frame.
- `column-selectors`: operators on selectors, mirrored comparisons.
- `expressions`: `over` with several names, `concatStr` with selectors.
- `inspection`: `describe` prints temporal values as Python.

## Differences from Polars

- Iterating a group-by yields the key as `seq[string]` (the key values as text, in `by`
  order), where Python yields a tuple of typed values.
- Python's `GroupBy.count()` is deprecated in favour of `len()`; Nanuq keeps both,
  `count` naming its column `count`.
- `head`, `tail` and iteration need a plain `groupBy` (not `groupByDynamic` or
  `rolling`), as in Python.
- Series aggregations already exist since 0.4 and return a one-value Series
  (`s.sum.item(float)`); Python returns the scalar.

- Nim has no reflected operators, so the mirroring is done by the overloads: arithmetic
  with a value on the left (`1 + col("a")`) is not mirrored and is named "literal",
  as in Python (`__radd__` puts the literal first too).

## Impact

- `src/rust/src/lib.rs`, `src/nanuq/ffi.nim`: `nq_lf_group_head` (group head/tail).
- `src/nanuq.nim`: the procs above, the rest in Nim over existing API.
- New `tests/test_bookneeds6.nim`.
