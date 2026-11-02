# Spec Delta

## ADDED Requirements

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
TBD
```

#### Scenario: ASCII
- **WHEN** a frame prints inside `withConfig(asciiTables = true)`
- **THEN** its borders use `+`, `-` and `|`
