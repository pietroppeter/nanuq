# Proposal

## Why

Some work has no Polars expression: a Nim library call, a lookup, a custom parser.
Python covers it with user functions (`map_elements` 7 book sections, `fold` 7,
`map_batches` 6), and the coverage map lists a Nim callback bridge for 0.5.

It is the seventh change of the 0.5 release.

## What Changes

- `e.mapElements(proc (x: T): U)`: a typed Nim proc or closure per value. Values are read
  as `T` (objects and named tuples for struct rows, seqs for lists), the result type is
  `dataType(U)`; nulls skip the call unless `T` is an `Option`.
- `e.mapBatches(proc (s: Series): Series)`, with `returnDtype` and `returnsScalar`: the
  whole column, or each group in a group-by.
- `fold`, `reduce`, `cumFold`, `cumReduce` with a `proc (acc, x: Series): Series`.
- `name.map(proc (name: string): string)`.
- `groupBy(...).mapGroups(proc (df: DataFrame): DataFrame)` on eager frames.
- A Nim exception in a callback becomes a `ComputeError` with its message.
- Series arithmetic broadcasts a Series of length 1 (as `fold`'s first accumulator is).

## Capabilities

### New Capabilities
- `callbacks`: Nim functions called by Polars.

## Differences from Polars

- `mapElements` is typed: the argument type says how values are read and the result type
  gives `return_dtype`, so neither is guessed from the first values as Python does.
- `skip_nulls` is the argument type: `proc (x: int)` skips nulls, `proc (x: Option[int])`
  gets them.
- Callbacks run one at a time (Polars' worker threads take a lock around Nim code), so
  they never run in parallel; Python has the GIL for the same reason.
- `mapGroups` is eager only and runs groups in order of first occurrence.
- No `rolling_map` or `cum_reduce` with `include_init`.

## Impact

- `src/rust/src/lib.rs` and `src/nanuq/ffi.nim`: C function pointers with a Nim
  environment (`NqUdfFn`, `NqNameFn`, `NqDropFn`), `nq_expr_map_batches`, `nq_fold`,
  `nq_expr_name_map`, `nq_series_clone`, `nq_udf_set_error`; the crate depends on
  `polars-plan` for function flags.
- `src/nanuq.nim`: the callback procs.
- New `tests/test_callbacks.nim`.
