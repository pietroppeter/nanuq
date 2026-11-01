# Proposal

## Why

Numerical work in Nim (linear algebra, statistics, machine learning with Flambeau or
Arraymancer's own layers) happens on Arraymancer tensors, the way Python moves from
Polars to NumPy with `to_numpy`. BACKLOG.md lists "Arraymancer tensors (S): copy numeric
columns to and from `Tensor[T]`", and the coverage map puts it in 0.4.

It is the ninth change of the 0.4 release, from the BACKLOG.md entry "Arraymancer
tensors".

## What Changes

- An optional module `nanuq/arraymancer`, like `nanuq/datamancer`: only it imports
  Arraymancer.
- `toTensor(series, T)`, `toTensor(df, column, T)` and `toTensor(df, T, columns)` (a 2-D
  tensor, one row per row), for T in int, float and bool; nulls become NaN in float
  tensors and raise `InvalidOperationError` otherwise.
- `toSeries(tensor, name)` for 1-D tensors and `toDataFrame(tensor, columns)` for 2-D
  tensors.
- CI already installs Datamancer, which depends on Arraymancer, so the new test runs
  there.

## Capabilities

### New Capabilities
- `arraymancer-interop`: copying numeric columns to and from Arraymancer tensors.

## Differences from Polars

- Python's `to_numpy` can be zero-copy; Nanuq copies (zero-copy needs the Arrow C Data
  Interface, a backlog item).
- The element type is given (`toTensor(float)`); Python infers the NumPy dtype.
- `toDataFrame` takes a 2-D tensor only (Python's `from_numpy` also takes 1-D arrays and
  an `orient`).

## Impact

- New `src/nanuq/arraymancer.nim` and `tests/test_arraymancer.nim`; `nanuq.nimble` test
  list; a comment in `.github/workflows/ci.yml`; BACKLOG.md entry removed.
