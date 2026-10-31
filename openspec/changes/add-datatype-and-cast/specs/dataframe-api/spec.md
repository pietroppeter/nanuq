# Spec Delta

## MODIFIED Requirements

### Requirement: HTML tables
`toHtml(df, maxRows = 10, maxCols = 75)` SHALL return the HTML that Python Polars'
`DataFrame._repr_html_` returns for the same data and limits: shape line, names and
dtypes header rows, cells formatted by Polars, and `…` rows and columns when truncated.
The one difference SHALL be the dtypes row, which shows Nim type names (`$` on
`DataType`).

#### Scenario: Same as Python
- **WHEN** `toHtml` is called on `penguins()`
- **THEN** the result equals what Python Polars' `_repr_html_` returns for the same CSV read with `null_values="NA"`, with the dtypes row mapped to Nim names

#### Scenario: Truncation
- **WHEN** a DataFrame with 344 rows is rendered with `maxRows = 10`
- **THEN** the body shows rows 0 to 4, a `…` row, and rows 339 to 343

#### Scenario: Escaping and nulls
- **WHEN** a string cell holds `<b>` and another cell is null
- **THEN** the first is shown as `"&lt;b&gt;"` and the second as `null`
