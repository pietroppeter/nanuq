# Proposal

## Why

Nim code works with typed records. Getting rows out of a frame into objects (to feed a
template, a plotting call or a simulation), or building a frame from a `seq` of objects,
takes one `toList` or `series` call per column today. Python has `df.rows(named=True)`,
`iter_rows` and `pl.DataFrame(list_of_dicts)`; the Datamancer gap analysis lists "row
objects" as something Datamancer users expect, and the coverage map puts it in 0.4.

It is the tenth change of the 0.4 release.

## What Changes

- `df.rows(T)` returns a `seq[T]` and `df.iterRows(T)` iterates, for T an object or named
  tuple whose fields name columns; `df.row(i, T)` returns one row.
- `toDataFrame(seq[T])` builds a frame with one column per field.
- Field types: int, float, bool, string, temporal values (`Date`, `DateTime`, ...), Nim
  enums, and `Option` of these for columns with nulls.

## Capabilities

### New Capabilities
- `row-objects`: rows as typed Nim objects and back.

## Differences from Polars

- The row type is a Nim type chosen by the caller; Python returns tuples or dicts.
- Fields match columns by exact name (no style-insensitive matching), and columns
  without a field are ignored.
- `iterRows` reads whole columns first; Python's `iter_rows` buffers rows in chunks.

## Impact

- `src/nanuq.nim`: `rows`, `iterRows`, `row`, `toDataFrame`. No ABI change.
- New `tests/test_rows.nim`.
