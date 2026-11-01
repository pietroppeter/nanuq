# Spec Delta

## ADDED Requirements

### Requirement: Quoting, encoding and new column names
`readCsv` and `scanCsv` SHALL take `quoteChar = some('"')` (`none(char)` turns quoting off), `encoding = CsvEncoding.Utf8` (`Utf8Lossy` replaces invalid UTF-8 instead of raising) and `newColumns`, which renames the first columns.

```nim
import std/os
let path = getTempDir() / "lines.txt"
writeFile(path, "a \"quoted, line\nplain\n")
echo readCsv(path, separator = '\x01', hasHeader = false, quoteChar = none(char),
             newColumns = ["line"])
```

```text
TBD
```

#### Scenario: Invalid UTF-8
- **WHEN** a line holds the byte 0xFF and `encoding = CsvEncoding.Utf8Lossy`
- **THEN** the line is read, with a replacement character
