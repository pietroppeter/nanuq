# Design

## Context

Rust Polars' table formatter (`polars-core/src/fmt.rs`) reads `POLARS_FMT_MAX_ROWS`,
`POLARS_FMT_MAX_COLS`, `POLARS_TABLE_WIDTH` and `POLARS_FMT_STR_LEN` with
`std::env::var` every time a frame is formatted; negative values mean no limit. Python's
`pl.Config.set_tbl_rows` and friends set these variables. Python's `glimpse` and
`describe` are written in Python over expressions.

## Decisions

### Config through the process environment
Nim's `putEnv`/`delEnv` change the same process environment that Rust's `std::env::var`
reads, so no ABI function is needed. `withConfig` saves the four variables (value or
absent), applies the options with `setConfig`, runs the block in `try`/`finally`, and
restores them. It is a macro over `varargs[untyped]` because a template with defaulted
`int | Option[int]` parameters followed by a block does not match named arguments.

Options take `int | Option[int]`. In the setters, `none(int)` restores the default; in
`setConfig` and `withConfig`, an option left out is left unchanged.

### `glimpse` in Nim
Values are the first `maxItemsPerColumn` rows, read as `Option[string]`, which uses
Polars' formatting for non-string columns. Python formats them with `str()`, so booleans
become `True`/`False`; string values are quoted like Python's `repr` (single quotes,
double quotes when the value holds a single quote and no double quote, backslash
escapes). Names longer than `maxColnameLength` are cut with `…`.

### `describe` in Nim
For each column, the applicable metric expressions are selected in one query (count,
nullCount, mean, std, min, quantiles, max), each cast to f64 for numeric and boolean
columns and to str otherwise; the others are null in the result. The single result row
is then reshaped in Nim into the output frame. Percentile labels use Python's
`f"{q * 100:g}%"`.

## Risks / Trade-offs

- The environment is process-wide, so config is not thread-local, as in Python.
