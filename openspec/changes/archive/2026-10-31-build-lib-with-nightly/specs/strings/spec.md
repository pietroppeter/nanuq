# Spec Delta

## ADDED Requirements

### Requirement: Title case
`str.toTitlecase` SHALL upper-case the first letter of each word and lower-case the
rest, when the native library is built with the `nightly` feature, as the release
libraries are. With a library built without it, it SHALL raise `InvalidOperationError`
when the expression is built.

#### Scenario: Release library
- **WHEN** `str.toTitlecase` runs over "tour de france" with a release library
- **THEN** the result is "Tour De France"

#### Scenario: Stable build
- **WHEN** `str.toTitlecase` is called with a library built on stable Rust
- **THEN** `InvalidOperationError` is raised
