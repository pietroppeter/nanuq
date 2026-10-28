# datamancer-interop Specification

## Purpose
Converting DataFrames between Nanuq and Datamancer (`nanuq/datamancer`), so Datamancer
and ggplotnim code can use Polars for queries. Datamancer stays an optional dependency.

## Requirements

### Requirement: To Datamancer
`toDatamancer` SHALL copy every column, in order and with its name, into a Datamancer
DataFrame: integers as `int`, floats as `float`, booleans as `bool`, strings as `string`,
and any other dtype as `string` formatted by Polars.

#### Scenario: Penguins without nulls
- **WHEN** `penguins().dropNulls().toDatamancer` is called
- **THEN** the result has 333 rows, the same column names in order, and `body_mass_g` is an `int` column

### Requirement: Nulls to Datamancer
A column with nulls SHALL become an object column whose missing entries are Datamancer
`null` values and whose other entries hold the values.

#### Scenario: Body mass with nulls
- **WHEN** `penguins().toDatamancer` is called
- **THEN** `body_mass_g` is an object column with 2 `null` values, and `drop_null` on it leaves 342 rows

### Requirement: From Datamancer
`fromDatamancer` SHALL copy every column back in order: `int` to i64, `float` to f64,
`bool` to bool, `string` to str, constant columns repeated, and object columns of one
value kind plus nulls to that dtype with nulls. Other object columns SHALL raise
`NanuqError`.

#### Scenario: Round trip
- **WHEN** a Nanuq DataFrame is converted with `toDatamancer` and back with `fromDatamancer`
- **THEN** it has the same shape, columns, dtypes (for i64, f64, bool, str) and null counts

#### Scenario: Mixed object column
- **WHEN** a Datamancer object column holds both an int and a string
- **THEN** `fromDatamancer` raises `NanuqError` naming the column

### Requirement: Optional dependency
Importing `nanuq` SHALL NOT require Datamancer; only importing `nanuq/datamancer` does.

#### Scenario: Without Datamancer
- **WHEN** a program imports only `nanuq` on a machine without Datamancer
- **THEN** it compiles
