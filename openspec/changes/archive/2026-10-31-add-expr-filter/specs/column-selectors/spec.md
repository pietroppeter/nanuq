# Spec Delta

## MODIFIED Requirements

### Requirement: Selecting by name
`col(a, b, ...)` with two or more names, and `col(names)` with an `openArray[string]`,
SHALL return a `Selector` for those columns in that order, and `all()` SHALL select
every column. `col` with one name SHALL keep returning an `Expr`, and a name that starts
with `^` and ends with `$` SHALL be a regex.

```nim
let df = newDataFrame(series("weight_kg", [410.5]), series("weight_lb", [905.0]),
                      series("name", ["Nanuq"]))
echo df.select(col("^weight_.*$")).columns    # regex
echo df.select(col("name", "weight_kg")).columns
echo df.select(all()).columns
let wanted = @["weight_lb", "name"]
echo df.select(col(wanted)).columns
```

```text
@["weight_kg", "weight_lb"]
@["name", "weight_kg"]
@["weight_kg", "weight_lb", "name"]
@["weight_lb", "name"]
```

#### Scenario: Regex
- **WHEN** `select(col("^weight_.*$"))` runs on columns `weight_kg`, `weight_lb` and `name`
- **THEN** the result has columns `weight_kg` and `weight_lb`

#### Scenario: Names from a seq
- **WHEN** `select(col(@["c", "a"]))` runs on columns `a`, `b` and `c`
- **THEN** the result has columns `c` and `a`
