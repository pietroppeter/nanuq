# Spec Delta

## ADDED Requirements

### Requirement: Reading CSV from a stream
`readCsv` SHALL also take a Nim `Stream` instead of a path, read all of it when called,
and take every CSV read option.

```nim
import std/streams
let text = "station;bears\nNorth;3\nSouth;NA\n"
echo readCsv(newStringStream(text), separator = ';', nullValues = ["NA"])
```

```text
TBD
```

#### Scenario: Same options
- **WHEN** CSV text with `;` separators and "NA" is read from a stream with `separator = ';', nullValues = ["NA"]`
- **THEN** the result equals reading the same text from a file with those options

#### Scenario: Empty stream
- **WHEN** an empty stream is read
- **THEN** `NoDataError` is raised
