## ADDED Requirements

### Requirement: Filling nulls in whole frames
DataFrame and LazyFrame SHALL support `fillNull(value)`, filling the columns the value
fits (a number: numeric columns, where a float turns integer columns into Float64; a
string: String columns; a bool: Boolean columns), and `fillNull(strategy, limit)` on
every column (Python's `df.fill_null`).

```nim
let df = newDataFrame:
  peak: ["Dom", "Täschhorn"]
  m: [some(4545), none(int)]
  first_ascent: [some(1858), none(int)]
echo df.fillNull(0)
```

```text
```

#### Scenario: Float value
- **WHEN** `fillNull(0.5)` runs on a frame with an Int64 column with nulls
- **THEN** that column becomes Float64 and its nulls hold 0.5

#### Scenario: String value
- **WHEN** `fillNull("x")` runs on a frame with Int64 and String columns
- **THEN** only the String column is filled
