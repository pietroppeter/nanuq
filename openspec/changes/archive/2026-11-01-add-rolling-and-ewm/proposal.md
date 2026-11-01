# Proposal

## Why

Smoothing a noisy series is the first thing done with any measurement over time: a
7-day average of cases, a 30-year climate normal, NOAA's El Niño index (a 3-month
running mean of sea temperature anomalies). Nanuq has none of Polars' rolling or
exponentially weighted functions, and no way to fill a gap from its neighbours
(`interpolate`, which the O'Reilly chapter on missing values uses three times).

It is the third change of the 0.4 release.

## What Changes

- **Fixed windows**: `rollingSum`, `rollingMean`, `rollingMin`, `rollingMax`,
  `rollingMedian`, `rollingStd`, `rollingVar` and `rollingQuantile`, with `windowSize`,
  `weights`, `minSamples` and `center`.
- **Time windows**: the same functions with a `By` suffix (`rollingMeanBy(by, 7.days)`),
  over a sorted temporal or integer column, with `minSamples` and `closed`
  (`ClosedWindow`). Window sizes are std/times intervals or Polars duration strings, as in
  0.3's `dateRange`.
- **Exponentially weighted**: `ewmMean`, `ewmStd`, `ewmVar` with exactly one of `com`,
  `span`, `halfLife`, `alpha`, plus `adjust`, `bias`, `minSamples`, `ignoreNulls`.
- **Interpolation**: `interpolate(InterpolationMethod.Linear | Nearest)` and
  `interpolateBy(by)`.

## Capabilities

### New Capabilities
- `rolling-windows`: fixed and time-based rolling windows, exponentially weighted functions.

### Modified Capabilities
- `missing-values`: interpolation.

## Differences from Polars

- The decay parameters of `ewmMean` default to NaN, meaning "not given", and must be
  named (`ewmMean(span = 12)`); Python uses None. Rust takes only `alpha`; Nanuq converts
  `com`, `span` and `halfLife` the way Python does.
- `minSamples` follows Python 2's name (Rust: `min_periods`).
- The `By` variants take `by` as a column name or expression, and Nim intervals as well
  as Polars duration strings.
- Not included: `rollingMap` (needs Nim callbacks, 0.5), `rollingSkew`, `rollingKurtosis`,
  `rollingRank`, `ewmMeanBy`, and Python's `rolling_*` on frames (that is the rolling
  group-by in add-dynamic-group-by).

## Impact

- `src/rust/src/lib.rs`: `nq_expr_rolling`, `nq_expr_rolling_by`, `nq_expr_ewm`,
  `nq_expr_interpolate`, `NqBinaryFn.InterpolateBy`; `src/nanuq/ffi.nim`, `src/nanuq.nim`.
- New `tests/test_rolling.nim`.
