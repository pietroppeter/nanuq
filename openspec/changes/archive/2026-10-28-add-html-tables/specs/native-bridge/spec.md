# Spec Delta

## ADDED Requirements

### Requirement: Formatted cells
The bridge SHALL return a single cell as text formatted by Polars, as Python Polars'
`get_fmt` does: the value's display form, with strings in quotes and cut to a given
number of characters followed by `…`.

#### Scenario: Float cell
- **WHEN** a cell holding 5076.016260162602 is formatted
- **THEN** the text is the same as in Polars' text table, `5076.01626`

#### Scenario: Long string
- **WHEN** a string of 40 characters is formatted with a limit of 30
- **THEN** the text is a quote, its first 30 characters and `…`
