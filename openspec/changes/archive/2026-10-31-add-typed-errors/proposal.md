# Proposal

## Why

Every failure in Nanuq raises one `NanuqError`, so a script can't tell a missing column
from a strict cast that hit a bad value, and the 0.3 explainer wants exactly that: catch
the error a smudged result sheet causes and carry on. Python Polars raises a hierarchy of
typed exceptions (`ColumnNotFoundError`, `InvalidOperationError`, ...), each matching a
Rust `PolarsError` variant, and Nim picks an `except` branch by type.

This is the third change of the 0.3 release, following the dev log "Designing Nanuq 0.3",
section 6: rename `NanuqError` to `PolarsError`, add Python's subtypes, raise Nim's own
`IOError` for IO failures, and add `nq_last_error_kind` to the ABI.

## What Changes

- **BREAKING: `NanuqError` is renamed `PolarsError`**, the base of every Polars error.
- Subtypes of `PolarsError`, named as in Python: `ColumnNotFoundError`, `ComputeError`,
  `DuplicateError`, `InvalidOperationError`, `NoDataError`, `OutOfBoundsError`,
  `SchemaError`, `SchemaFieldNotFoundError`, `ShapeError`, `StructFieldNotFoundError`
  and `SqlError`. Each Rust variant raises its subtype; a variant wrapped in context
  raises the subtype of the error inside.
- **IO failures raise Nim's `IOError`** (e.g. reading a file that does not exist), not a
  `PolarsError`.
- Errors Nanuq raises itself in Nim use the closest subtype: reading a column with nulls
  as a plain type, casting to a dtype Nanuq does not model, describing a frame with no
  columns and converting an unsupported Datamancer column raise `InvalidOperationError`.
- The C ABI adds `nq_last_error_kind()`, which tells the kind of the last error
  (`NqErrorKind`).

## Capabilities

### New Capabilities

None.

### Modified Capabilities
- `dataframe-api`: errors are typed; `PolarsError` replaces `NanuqError` in every
  requirement.
- `native-bridge`: `nq_last_error_kind`, and `NqErrorKind` joins the enums kept in the
  same order.
- `combining-frames`, `csv-io`, `data-types`, `datamancer-interop`, `frame-verbs`,
  `inspection`, `missing-values`: requirements that raised `NanuqError` now raise
  `PolarsError` (or a named subtype).

## Differences from Polars

Expected differences from Polars' Rust and Python APIs:

- **One base type, not Rust's enum**: Rust has one `PolarsError` enum with variants;
  Nanuq, like Python, has a type per variant. Python's base is `PolarsError` too.
- **Names**: `SchemaMismatch` is `SchemaError` and `ShapeMismatch` is `ShapeError`, as in
  Python. Python's two SQL errors (`SQLInterfaceError`, `SQLSyntaxError`) are one
  `SqlError`, since Nanuq has no SQL yet. `StringCacheMismatch` and `AssertionError` raise
  the base `PolarsError` (Nanuq has no string cache, and Nim's `AssertionDefect` is a
  defect, not an error).
- **IO**: Python raises built-in `FileNotFoundError` / `OSError`; Nanuq raises Nim's
  `IOError`, which is not a `PolarsError`.
- **Panics** inside Polars raise the base `PolarsError` with the panic message; Python
  raises `PanicException`, which is not an `Exception`.
- Python's warnings (`PolarsWarning` and friends) have no counterpart.

## Impact

- `src/rust/src/lib.rs`: a thread-local error kind next to the message, set when a
  `PolarsError` is converted; `nq_last_error_kind`; `NqErrorKind`.
- `src/nanuq/ffi.nim` and `src/nanuq.nim`: the declaration, the error types, `raiseLast`
  picking the type.
- `src/nanuq/datamancer.nim`, tests, README and docs: `PolarsError` instead of
  `NanuqError`.
