# Proposal

## Why

Tests of code that builds frames need a good equality check: one that says *where*
two frames differ, compares floats with a tolerance, and can ignore row or column
order. Python Polars ships it as `polars.testing` (`assert_frame_equal` and friends);
the roadmap lists "testing helpers" in 0.6, and Nanuq's own tests and the book's checks
would read better with it than with `equals` plus `toList`.

It is the eighth change of the 0.6 release.

## What Changes

- New module `nanuq/testing` (no extra dependency) with `assertFrameEqual`,
  `assertFrameNotEqual`, `assertSeriesEqual`, `assertSeriesNotEqual`.
- Options as in Python: `checkRowOrder`, `checkColumnOrder`, `checkDtypes`,
  `checkNames` (Series), `checkOrder` (Series), `checkExact`, `rtol`, `atol`.
- Failures raise `AssertionDefect` whose message names the first difference
  (columns, heights, dtypes, or the column, row and both values).

## Capabilities

### New Capabilities
- `testing-helpers`: assertions comparing frames and Series.

## Differences from Polars

- Python raises `AssertionError`; Nanuq raises `AssertionDefect`, as `doAssert` does,
  which `std/unittest` reports as a failed test.
- Python's `rel_tol`/`abs_tol` are `rtol`/`atol` (the names Python used before 1.0 and
  NumPy uses); there is no `categorical_as_str` (compare with `checkDtypes = false`).
- Messages are Nanuq's own wording, not Polars'.

## Impact

- New `src/nanuq/testing.nim`, new `tests/test_testing.nim`.
