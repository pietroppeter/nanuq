# Proposal

## Why

[Datamancer](https://github.com/SciNim/Datamancer) is Nim's pure-Nim dataframe, and
ggplotnim plots only Datamancer DataFrames. Today moving data across means one `toSeq`
per column and spelling out every column name (see the "Plotting with ggplotnim" post).
A conversion both ways lets Datamancer code hand heavy queries to Polars and get the
result back, and makes plotting a Nanuq result a single call.

This takes up the BACKLOG.md entry "Datamancer interop both ways" (Ecosystem).

## What Changes

- New optional module `nanuq/datamancer` (it imports `pkg/datamancer`; Nanuq itself does
  not require Datamancer):
  - `toDatamancer(df): datamancer.DataFrame` copies every column. Integer columns become
    `int` columns, floats `float`, booleans `bool`, strings `string`. Any other dtype
    (dates, categoricals, …) becomes a `string` column formatted by Polars, as
    `toSeq(…, string)` does.
  - A column with nulls becomes a Datamancer object column whose missing entries are
    Datamancer's `null` values, so `drop_null` and `toTensor(…, dropNulls = true)` work
    on it. Null-free columns keep their native type.
  - `fromDatamancer(dm): nanuq.DataFrame` copies every column back: `int` to i64,
    `float` to f64, `bool`, `string` to str, constant columns repeated to the frame's
    length, and object columns holding one kind of value (plus nulls) to that dtype
    with nulls. Mixed object columns raise `NanuqError`.
- Column order and names are kept both ways.
- The "Plotting with ggplotnim" post uses `toDatamancer` instead of one `toSeq` per
  column, and keeps its explanation of what happens underneath.
- CI installs Datamancer for the tests.

## Capabilities

### New Capabilities
- `datamancer-interop`: converting DataFrames between Nanuq and Datamancer.

### Modified Capabilities
None.

## Differences from Polars

- **Python** has the same idea for pandas: `df.to_pandas()` and `pl.from_pandas(pdf)`.
  Nanuq follows those names in camelCase, as a function in a separate module (Nim
  cannot add methods, and Datamancer stays optional, like pandas is for Polars).
- **Nulls.** `to_pandas` turns nulls into `NaN` or `None` depending on the dtype; Nanuq
  uses Datamancer's `null` values in an object column, Datamancer's own way to mark
  missing data.
- **Rust** has no equivalent.
- **Copies.** Like `to_pandas` without pyarrow-backed columns, the data is copied.

## Impact

- `src/nanuq/datamancer.nim` (new). No bridge change: it is built on `toSeq` and
  `series`, including their `Option` variants.
- `tests/test_datamancer.nim` (new); `.github/workflows/ci.yml` installs Datamancer in
  the test job.
- `docs/blog/plotting_with_ggplotnim.nim`, README (one line on the module).
