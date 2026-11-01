## ADDED Requirements

### Requirement: Dates from parts
`date(year, month, day)` SHALL build a Date column when at least one part is an
expression; each part SHALL be an integer expression or a number, as Polars' `date`.
Invalid dates (month 13, 30 February) SHALL raise when the query runs. With three
numbers `date` SHALL keep returning a `Date` value.

```nim
let seasons = newDataFrame:
  year: [1982, 1997, 2015]
  month: [12, 11, 11]
echo seasons.select(date(col.year, col.month, 15).alias("mid"))
echo date(2026, 2, 1)
```

```text
```

#### Scenario: Mixed parts
- **WHEN** `date(col.year, 1, 1)` runs on years 1950 and 1951
- **THEN** the result is the dates 1950-01-01 and 1951-01-01

#### Scenario: Invalid date
- **WHEN** `date(col.year, 2, 30)` runs
- **THEN** a `PolarsError` is raised
