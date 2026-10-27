# Spec Delta

## ADDED Requirements

### Requirement: Reading CSV from a string
`readCsvString` SHALL read CSV text held in memory, with a header row and the same
`nullValues` option as `readCsv`, and SHALL raise `NanuqError` on malformed input.

#### Scenario: Same result as from a file
- **WHEN** the contents of a CSV file are read with `readCsvString`
- **THEN** the result equals `readCsv` on that file

#### Scenario: Null markers
- **WHEN** `readCsvString("a\n1\nNA\n", nullValues = ["NA"])` is called
- **THEN** column "a" is an integer column with one null
