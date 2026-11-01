# Spec Delta

## ADDED Requirements

### Requirement: Rows as objects
`df.rows(T)` SHALL return the rows as a `seq[T]` and `df.iterRows(T)` SHALL iterate them,
for T an object or named tuple whose fields are named after columns, and `df.row(i, T)`
SHALL return row `i` (negative from the end). Fields SHALL be int, float, bool, string,
temporal values, Nim enums, or `Option` of these; a null read into a plain field SHALL
raise `InvalidOperationError`, and a field without a column `ColumnNotFoundError`.

```nim
type Reading = object
  station: string
  rain: float
let df = newDataFrame:
  station: ["Lima", "Piura", "Tumbes"]
  rain: [1.5, 80.0, 95.0]
  year: [1998, 1998, 1998]
for r in df.iterRows(Reading):
  echo r.station, ": ", r.rain
echo df.row(-1, tuple[station: string, year: int])
```

```text
TBD
```

#### Scenario: Missing column
- **WHEN** `rows` is called with a type that has a field `wind` and the frame has no column `wind`
- **THEN** `ColumnNotFoundError` is raised

### Requirement: Objects to a frame
`toDataFrame(rows)` SHALL build a frame from a `seq` or array of objects or named tuples,
with one column per field in field order; `Option` fields SHALL give columns with nulls.

```nim
type Event = object
  year: int
  peak: Option[float]
let events = @[Event(year: 1997, peak: some(2.4)), Event(year: 2014, peak: none(float))]
echo events.toDataFrame
```

```text
TBD
```

#### Scenario: Round trip
- **WHEN** a seq of objects is turned into a frame and read back with `rows`
- **THEN** the result equals the original seq
