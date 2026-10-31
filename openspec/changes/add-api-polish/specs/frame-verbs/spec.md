# Spec Delta

## MODIFIED Requirements

### Requirement: Row windows
LazyFrame and DataFrame SHALL support `head(n = 5)`, `tail(n = 5)`, `slice(offset)` and
`slice(offset, length)`. A negative offset SHALL count from the end. `reverse()` SHALL
reverse the row order.

```nim
let df = newDataFrame(series("n", [1, 2, 3, 4, 5]))
echo df.tail(2).toList("n", int)
echo df.slice(-3, 2).toList("n", int)       # negative offset counts from the end
echo df.slice(1).toList("n", int)           # to the end
echo df.reverse.toList("n", int)
```

```text
@[4, 5]
@[3, 4]
@[2, 3, 4, 5]
@[5, 4, 3, 2, 1]
```

#### Scenario: Tail
- **WHEN** `tail(2)` runs on rows 1 to 5
- **THEN** the result is rows 4 and 5

#### Scenario: Slice from the end
- **WHEN** `slice(-3, 2)` runs on rows 1 to 5
- **THEN** the result is rows 3 and 4

#### Scenario: Slice to the end
- **WHEN** `slice(1)` runs on rows 1 to 5
- **THEN** the result is rows 2 to 5
