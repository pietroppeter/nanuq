# Spec Delta

## ADDED Requirements

### Requirement: Comment lines
`readCsv` and `scanCsv` SHALL skip lines starting with `commentPrefix` (none when empty).

```nim
import std/streams
echo readCsv(newStringStream("# measured 2026\nbear,kg\nAda,410\n"), commentPrefix = "#")
```

```text
TBD
```

#### Scenario: No prefix
- **WHEN** a CSV starting with "# note" is read without `commentPrefix`
- **THEN** "# note" is the first column name
