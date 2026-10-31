# column-selectors Specification

## Purpose
Selecting several columns at once, by Nim type, by name, by regex or all of them, minus
excluded names, and renaming the outputs of such expressions.

## Requirements

### Requirement: Selecting by Nim type
`col` SHALL accept Nim types and typeclasses and return a `Selector`.
- `SomeNumber`, `SomeInteger`, `SomeSignedInt`, `SomeUnsignedInt` and `SomeFloat` SHALL
  select the matching Polars dtype category.
- A concrete type SHALL select the dtype `dataType` gives it.
- Several types SHALL select their union.
- A type without a dtype SHALL not compile.

#### Scenario: Numeric columns
- **WHEN** `select(col(SomeNumber))` runs on columns `station` (str), `bears` (i64) and `weight` (f64)
- **THEN** the result has columns `bears` and `weight`

#### Scenario: Exact types
- **WHEN** `select(col(float, string))` runs on the same frame
- **THEN** the result has columns `station` and `weight`

#### Scenario: Not a column type
- **WHEN** `col(seq[int])` is compiled
- **THEN** compilation fails

### Requirement: Selecting by name
`col(a, b, ...)` with two or more names SHALL return a `Selector` for those columns in that
order, and `all()` SHALL select every column. `col` with one name SHALL keep returning
an `Expr`, and a name that starts with `^` and ends with `$` SHALL be a regex.

#### Scenario: Regex
- **WHEN** `select(col("^weight_.*$"))` runs on columns `weight_kg`, `weight_lb` and `name`
- **THEN** the result has columns `weight_kg` and `weight_lb`

### Requirement: Excluding columns
`Selector` SHALL support `exclude(names: varargs[string])`, which removes the named columns
from the selection.

#### Scenario: All but one
- **WHEN** `select(all().exclude("id"))` runs on columns `id`, `a` and `b`
- **THEN** the result has columns `a` and `b`

### Requirement: Selectors as expressions
A `Selector` SHALL convert to `Expr` automatically. An expression built from it SHALL
apply to every selected column and keep each column's name.

#### Scenario: Mean per group of every numeric column but one
- **WHEN** a frame is grouped by `station` and aggregated with `col(SomeNumber).exclude("cubs").mean`
- **THEN** the result has `station` and one mean column per remaining numeric column, with the original names

### Requirement: Output name suffix and prefix
`Expr` SHALL support `name.suffix(s)` and `name.prefix(s)`, which append or prepend `s` to
the name of every column the expression produces.

#### Scenario: Two aggregations of one selector
- **WHEN** `agg(col(SomeFloat).mean.name.suffix("_mean"), col(SomeFloat).max.name.suffix("_max"))` runs on float columns `a` and `b`
- **THEN** the result has columns `a_mean`, `b_mean`, `a_max` and `b_max`
