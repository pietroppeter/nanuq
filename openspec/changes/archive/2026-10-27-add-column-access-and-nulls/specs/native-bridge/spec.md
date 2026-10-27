# Spec Delta

## ADDED Requirements

### Requirement: Columns cross in bulk
Reading a whole column into Nim SHALL take a constant number of FFI calls, independent
of the number of rows, and SHALL transfer a validity mask alongside the values so
nulls are not lost or replaced by placeholder values.

#### Scenario: Large column
- **WHEN** a 1,000,000-row float column is read into a Nim seq
- **THEN** at most two FFI calls are made for that column

#### Scenario: Validity
- **WHEN** a column with nulls crosses the boundary
- **THEN** Nim receives, for every row, whether the value is valid
