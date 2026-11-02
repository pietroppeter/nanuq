# inspection Specification

## Purpose
Looking at a frame: `glimpse`, `describe`, and the display configuration (`setTbl*`, `setConfig`, `withConfig`).

## Requirements

### Requirement: glimpse
`glimpse(df, maxItemsPerColumn = 10, maxColnameLength = 50)` SHALL return, as a string,
the lines `Rows: <height>` and `Columns: <width>`, then one line per column:
`$ <name> <<dtype>> <values>`, with names left-aligned and dtypes right-aligned to a
common width, and the first `maxItemsPerColumn` values joined by ", ". Nulls SHALL be
`null`, booleans `True`/`False`, and strings quoted as Python's `repr` quotes them. Names
longer than `maxColnameLength` SHALL be cut and end with `…`.

```nim
let df = newDataFrame:
  rider: ["Pogačar", "Seixas", "Van der Poel"]
  wins: [22, 8, nil]
  pro: [true, false, true]
  race: ["Giro d'Italia", "Tour", "Vuelta"]
echo df.glimpse
```

```text
Rows: 3
Columns: 4
$ rider  <str> 'Pogačar', 'Seixas', 'Van der Poel'
$ wins   <i64> 22, 8, null
$ pro   <bool> True, False, True
$ race   <str> "Giro d'Italia", 'Tour', 'Vuelta'

```

#### Scenario: Long frame
- **WHEN** a column of 100 rows is glimpsed with `maxItemsPerColumn = 3`
- **THEN** its line shows the first 3 values only

#### Scenario: Long name
- **WHEN** a column named with 60 characters is glimpsed
- **THEN** its line shows the first 49 characters followed by `…`

### Requirement: describe
`describe(percentiles = [0.25, 0.5, 0.75], interpolation = Nearest)` on DataFrame and
LazyFrame SHALL return a DataFrame with a `statistic` column holding `count`,
`null_count`, `mean`, `std`, `min`, one row per percentile (labelled as `25%`) and `max`,
followed by one column per input column: f64 for numeric and boolean columns, str for
the others, and null where a statistic does not apply.

```nim
let df = newDataFrame:
  rider: ["Pogačar", "Seixas", "Van der Poel"]
  wins: [22, 8, nil]
  pro: [true, false, true]
echo df.describe
```

```text
shape: (9, 4)
┌────────────┬──────────────┬──────────┬──────────┐
│ statistic  ┆ rider        ┆ wins     ┆ pro      │
│ ---        ┆ ---          ┆ ---      ┆ ---      │
│ str        ┆ str          ┆ f64      ┆ f64      │
╞════════════╪══════════════╪══════════╪══════════╡
│ count      ┆ 3            ┆ 2.0      ┆ 3.0      │
│ null_count ┆ 0            ┆ 1.0      ┆ 0.0      │
│ mean       ┆ null         ┆ 15.0     ┆ 0.666667 │
│ std        ┆ null         ┆ 9.899495 ┆ null     │
│ min        ┆ Pogačar      ┆ 8.0      ┆ 0.0      │
│ 25%        ┆ null         ┆ 8.0      ┆ null     │
│ 50%        ┆ null         ┆ 22.0     ┆ null     │
│ 75%        ┆ null         ┆ 22.0     ┆ null     │
│ max        ┆ Van der Poel ┆ 22.0     ┆ 1.0      │
└────────────┴──────────────┴──────────┴──────────┘
```

#### Scenario: Custom percentiles
- **WHEN** `describe(percentiles = [0.1, 0.9])` runs
- **THEN** the statistic column holds `count`, `null_count`, `mean`, `std`, `min`, `10%`, `90%` and `max`

#### Scenario: Statistics that do not apply
- **WHEN** a frame with a string and a boolean column is described
- **THEN** mean, std and percentiles are null for the string column, and std and percentiles for the boolean one

#### Scenario: No columns
- **WHEN** `newDataFrame().describe` runs
- **THEN** `PolarsError` is raised

### Requirement: Display config
The API SHALL set how tables print with `setTblRows(n)`, `setTblCols(n)`,
`setTblWidthChars(n)` and `setFmtStrLengths(n)`, where `-1` means no limit and
`none(int)` restores Polars' default; with `setFloatPrecision(n)`, the number of decimal
places floats print with (`none(int)` for Polars' default); with `setConfig(tblRows,
tblCols, tblWidthChars, fmtStrLengths, floatPrecision)`, where options left out are
unchanged; and with `resetConfig()`, which restores every default. The settings SHALL apply to every later `$` of a DataFrame.

```nim
let df = newDataFrame(series("n", [1, 2, 3, 4, 5, 6]))
setTblRows(4); setFmtStrLengths(10)
echo df
setConfig(tblRows = 2, tblCols = 5)
echo df
resetConfig()
```

```text
shape: (6, 1)
┌─────┐
│ n   │
│ --- │
│ i64 │
╞═════╡
│ 1   │
│ 2   │
│ …   │
│ 5   │
│ 6   │
└─────┘
shape: (6, 1)
┌─────┐
│ n   │
│ --- │
│ i64 │
╞═════╡
│ 1   │
│ …   │
│ 6   │
└─────┘
```

#### Scenario: Float precision
- **WHEN** `setConfig(floatPrecision = 2)` is called and a frame holding 0.05333 prints
- **THEN** the value shows as 0.05

#### Scenario: No limit
- **WHEN** `setTblRows(-1)` is called and a frame of 50 rows is printed
- **THEN** all 50 rows are shown

#### Scenario: Reset
- **WHEN** `setTblRows(2)` and then `resetConfig()` are called
- **THEN** a frame of 10 rows prints all 10 rows again

### Requirement: Scoped display config
`withConfig(options): body` SHALL apply the named options (`tblRows`, `tblCols`,
`tblWidthChars`, `fmtStrLengths`, `floatPrecision`) while `body` runs, and SHALL restore the previous
settings afterwards, also when `body` raises.

```nim
let df = newDataFrame(series("n", [1, 2, 3, 4, 5, 6]))
withConfig(tblRows = 2):
  echo df
echo df.shape, " ", ($df).count('\n')
```

```text
shape: (6, 1)
┌─────┐
│ n   │
│ --- │
│ i64 │
╞═════╡
│ 1   │
│ …   │
│ 6   │
└─────┘
(6, 1) 12
```

#### Scenario: Restored after an exception
- **WHEN** the body of `withConfig(tblRows = 2)` raises
- **THEN** the exception propagates and the row limit is back to its previous value

### Requirement: Describe prints temporal values as Python
`describe` SHALL print Datetime statistics and the mean of a Date column as `YYYY-MM-DD HH:MM:SS`, with a fraction only when it is not zero.

```nim
let df = newDataFrame(series("d", @[date(1986, 9, 1), date(1986, 9, 7)]))
echo df.describe
```

```text
shape: (9, 2)
┌────────────┬─────────────────────┐
│ statistic  ┆ d                   │
│ ---        ┆ ---                 │
│ str        ┆ str                 │
╞════════════╪═════════════════════╡
│ count      ┆ 2                   │
│ null_count ┆ 0                   │
│ mean       ┆ 1986-09-04 00:00:00 │
│ std        ┆ null                │
│ min        ┆ 1986-09-01          │
│ 25%        ┆ 1986-09-01          │
│ 50%        ┆ 1986-09-07          │
│ 75%        ┆ 1986-09-07          │
│ max        ┆ 1986-09-07          │
└────────────┴─────────────────────┘
```

#### Scenario: Date mean
- **WHEN** the mean of 1986-09-01 and 1986-09-07 is described
- **THEN** it reads `1986-09-04 00:00:00`

### Requirement: Table formatting options
`setTblFormatting(TableFormat, roundedCorners)`, `setAsciiTables`,
`setTblHideColumnDataTypes`, `setTblHideColumnNames`, `setTblHideDataframeShape`,
`setTblHideColumnSeparator`, `setTblDataframeShapeBelow`, `setTblColumnDataTypeInline`,
`setTblCellAlignment`, `setTblCellNumericAlignment` and `setFmtTableCellListLen` SHALL
change how frames print; `setConfig` and `withConfig` SHALL take `tblFormatting`,
`asciiTables`, `tblHideColumnDataTypes`, `tblHideColumnNames`, `tblHideDataframeShape`
and `tblCellAlignment`, and `resetConfig` SHALL undo them all.

```nim
let df = newDataFrame(series("bear", @["Ada"]), series("kg", @[410]))
withConfig(tblFormatting = TableFormat.Markdown, tblHideDataframeShape = true):
  echo df
```

```text
| bear | kg  |
| ---  | --- |
| str  | i64 |
|------|-----|
| Ada  | 410 |
```

#### Scenario: ASCII
- **WHEN** a frame prints inside `withConfig(asciiTables = true)`
- **THEN** its borders use `+`, `-` and `|`
