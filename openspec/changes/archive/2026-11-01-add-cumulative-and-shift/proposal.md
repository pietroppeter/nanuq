# Proposal

## Why

Comparing a row with the rows before it is the heart of time-series work: day-to-day
change, running totals, records so far, how long a streak lasts. Nanuq has `over` and
`rank` but no `shift`, `diff` or cumulative functions, so a port of a "change since
yesterday" query needs a self-join. The O'Reilly chapter 8 sections "Operations that
accumulate" and the Packt window recipes stop here, and so does the 0.4 explainer
(El Niño events are runs of consecutive warm seasons).

It is the second change of the 0.4 release.

## What Changes

- **Shifting and differences**: `shift(n = 1, fillValue)`, `diff(n = 1, nullBehavior)`
  with a `NullBehavior` pure enum (`Ignore`, `Drop`), and `pctChange(n = 1)`.
- **Cumulative functions**: `cumSum`, `cumProd`, `cumMin`, `cumMax`, `cumCount`, each
  with `reverse = false`.
- **Runs and peaks**: `rleId` (an id that grows by one each time the value changes),
  `peakMax`, `peakMin`.
- **More aggregations**: `product`, `mode`, `argMin`, `argMax`, `skew(bias = true)`,
  `kurtosis(fisher = true, bias = true)`.

## Capabilities

### New Capabilities
- `cumulative-functions`: shift, diff, pctChange, cumulative functions, runs and peaks.

### Modified Capabilities
- `expressions`: more aggregations (product, mode, argMin, argMax, skew, kurtosis).

## Differences from Polars

- `shift` with a fill value is one proc with a named `fillValue` (Python's `fill_value`,
  Rust's `shift_and_fill`).
- `diff`'s `nullBehavior` is the `NullBehavior` pure enum (Python takes the strings
  "ignore" and "drop").
- `n` is an `int` (Rust and Python also accept an expression); that covers every use in
  the Polars docs and books.
- `rle` (which returns a Struct) waits for Struct columns in 0.5; `rleId` is here.

## Impact

- `src/rust/src/lib.rs`: `NqUnary` grows (cumulative functions, product, mode, argMin,
  argMax, rleId, peaks), `nq_expr_shift`, `nq_expr_diff`, `nq_expr_pct_change`,
  `nq_expr_moment`; `src/nanuq/ffi.nim`, `src/nanuq.nim`.
- New `tests/test_cumulative.nim`.
