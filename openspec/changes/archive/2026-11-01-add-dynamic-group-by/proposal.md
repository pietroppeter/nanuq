# Proposal

## Why

Time series are grouped by calendar windows (monthly totals, weekly means, the three
months around each month) and matched by nearest time (the reading at or before each
event). Polars does this with `group_by_dynamic`, `rolling` and `join_asof`. Without
them a Nanuq user has to truncate dates and join on them, which can't express
overlapping windows or "the last value before". The O'Reilly chapters 1 and 13 and the
user guide's time-series pages stop on `group_by_dynamic` (4 sections), and the 0.4
explainer needs `joinAsof` to line up El Niño seasons with monthly temperatures.

It is the seventh change of the 0.4 release.

## What Changes

- **`groupByDynamic(indexColumn, every, period, offset, includeBoundaries, closed,
  label, groupBy, startBy)`** on DataFrame and LazyFrame, followed by `agg`. `Label`
  and `StartBy` are pure enums; intervals are std/times intervals or Polars duration
  strings.
- **`rolling(indexColumn, period, offset, closed, groupBy)`**, the rolling group-by: one
  window per row, followed by `agg`.
- **`joinAsof(other, on | leftOn + rightOn, by | byLeft + byRight, strategy, suffix,
  tolerance, allowExactMatches, checkSortedness, coalesce)`** with an `AsofStrategy`
  pure enum (`Backward`, `Forward`, `Nearest`) and a tolerance given as an interval or a
  number.
- Small parameter types with converters, so that optional parameters accept several
  types: `OptInterval` (interval or string), `JoinKey` (name or expression),
  `AsofTolerance` (interval, string or number).

## Capabilities

### New Capabilities
- `temporal-grouping`: dynamic and rolling group-by, as-of joins.

## Differences from Polars

- `groupBy` inside `groupByDynamic` and `rolling` takes expressions
  (`groupBy = [col.site]`); Python also takes names.
- `joinAsof`'s `on`, `leftOn` and `rightOn` take one key each, as in Python.
- `rolling` on a frame is the rolling group-by, as in Python; the rolling expression
  functions are `rollingMean` and friends.

## Impact

- `src/rust/src/lib.rs`: `nq_lf_group_by_dynamic_agg`, `nq_lf_rolling_agg`,
  `nq_lf_join_asof`; `src/nanuq/ffi.nim`; `src/nanuq.nim` (`LazyGroupBy` gains the
  window options).
- New `tests/test_timegroups.nim`.
