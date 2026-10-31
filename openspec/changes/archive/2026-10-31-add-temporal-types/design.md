# Design

## Values cross as physical integers

Polars stores Date as i32 days, Datetime and Duration as i64 in their time unit, and Time
as i64 nanoseconds. Nim values are converted to these integers on the Nim side
(`toPhysical`), sent with the existing integer buffers, and cast to the temporal dtype in
Rust (`nq_series_new_temporal`, `nq_expr_lit_temporal`). Reading back goes the other way
through `nq_expr_to_physical`. No date logic lives in Rust.

## Dtype specs

A dtype is no longer a single enum code: Datetime carries a unit and a zone, and the
categorical change will carry categories. `NqDtypeSpec` (code, time unit, zone
C string, categories pointer and count) crosses the ABI by value wherever a dtype did.
Nim keeps the zone strings alive for the call (`toSpecs`).

## `Date` and `TimeOfDay`

`Date` is `distinct int32`, the same days count Polars stores, so it round-trips without
loss and sorts as an integer. `TimeOfDay` wraps nanoseconds since midnight. Both convert
to and from `DateTime` (`toDateTime`, `toDate`, `toTimeOfDay`). They are deliberately
small: calendar arithmetic goes through `DateTime` or the `dt` namespace.

## Instants, not wall-clock times

A std/times `DateTime` is always an instant with a zone (local or UTC). Nanuq stores its
UTC instant. A naive column therefore holds UTC wall-clock times; a zoned column the same
instant in that zone. Reading back always gives UTC `DateTime`s, because std/times cannot
represent IANA zones. This keeps the conversion lossless and documented, at the price of
differing from Python for naive local times.

## `dt` as one entry point

As with `str`, the namespace is a `distinct Expr`, and Rust has one `nq_expr_dt(expr, op,
arg expr, string, flag, unit, nonExistent)` that switches on `NqDtOp`, so new functions
need no new ABI symbols.

## Intervals

`toPolarsInterval(TimeInterval)` writes Polars' duration language (`1y2mo3d4h`). A
TimeInterval with mixed signs has no single Polars string, so it raises `ValueError`.
