## MODIFIED Requirements

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
