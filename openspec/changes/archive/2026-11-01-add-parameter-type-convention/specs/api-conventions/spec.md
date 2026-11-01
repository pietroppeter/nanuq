## ADDED Requirements

### Requirement: Parameters that take several types use converter types
Where Python Polars lets a parameter take values of different types (a name or a list of
names, a duration string or a number) and the parameter needs a default, Nanuq SHALL use
a small exported object type with a `converter` from each accepted type, instead of a
generic union (`string | openArray[string] = []` does not compile with a default in Nim)
or one overload per combination. The existing types are `ColumnNames` (a name, a seq or an
array of names), `OptInterval` (a std/times interval or a duration string), `JoinKey` (a
column name or an expression) and `AsofTolerance` (an interval, a duration string, an int
or a float). A new parameter of this kind SHALL reuse one of them when it fits, and a new
type SHALL be listed here. Converters SHALL only convert into these types, so they apply
only where such a parameter appears.

```nim
let df = newDataFrame:
  year: [1997, 1997, 1998]
  months: ["JJA", "SON", "JJA"]
  anomaly: [1.5, 2.3, -0.2]
echo df.pivot("months", index = "year", values = "anomaly").columns
echo df.pivot(["months"], index = @["year"], values = "anomaly").columns
```

```text
```

#### Scenario: One name or a list
- **WHEN** user code passes `index = "year"` or `index = ["year", "month"]` to `pivot`
- **THEN** both compile and mean one or two index columns

#### Scenario: Default left out
- **WHEN** user code calls `joinAsof(other, on = "t")` without `tolerance`
- **THEN** it compiles, and no tolerance is applied
