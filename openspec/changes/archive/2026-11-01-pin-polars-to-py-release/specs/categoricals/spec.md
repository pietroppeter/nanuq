# Spec Delta

## MODIFIED Requirements

### Requirement: The cat namespace
`e.cat` SHALL give access to `lenBytes`, `lenChars`, `startsWith(prefix)`,
`endsWith(suffix)` and `slice(offset, length)` on Categorical and Enum columns.
`e.toPhysical` SHALL give the category indices. `getCategories`, removed in Polars 2.0,
SHALL be a compile-time error pointing to `unique()` and the dtype's `categories`.

```nim
type Medal = enum Gold, Silver, Bronze
let df = newDataFrame:
  medal: [Silver, Gold, Silver]
echo df.select(col.medal.cat.lenChars)
echo df.select(col.medal.toPhysical).toList("medal", int)
echo df.dtype("medal").categories
```

```text
TBD
```

#### Scenario: All categories
- **WHEN** the categories of an Enum column holding only Silver and Gold are needed
- **THEN** `dtype(df, c).categories` gives Gold, Silver and Bronze
