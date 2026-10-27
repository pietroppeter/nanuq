# Spec Delta

## Purpose

Small, well-known datasets loadable with one call and no file path, for examples, tests
and documentation. They are bundled for convenience during early development and are
expected to move out of the library later.

## ADDED Requirements

### Requirement: Penguins dataset
`nanuq/datasets` SHALL provide `penguins()` returning the palmerpenguins table: 344 rows
and the columns species, island, bill_length_mm, bill_depth_mm, flipper_length_mm,
body_mass_g, sex and year, with "NA" fields as nulls.

#### Scenario: Shape and columns
- **WHEN** `penguins()` is called
- **THEN** the result has shape (344, 8) and the columns listed above, in that order

#### Scenario: Missing values
- **WHEN** `penguins()` is called
- **THEN** `nullCount` is 2 for body_mass_g and 11 for sex, and body_mass_g is an integer column

### Requirement: Loading without files or network
Bundled datasets SHALL load without reading files at run time or using the network.

#### Scenario: Different working directory
- **WHEN** a compiled program calls `penguins()` from any working directory
- **THEN** the dataset loads

### Requirement: Licensing
Every bundled dataset SHALL ship with its source, credit and license in the repository,
and SHALL be under a license that allows redistribution.

#### Scenario: Penguins credit
- **WHEN** someone looks for where penguins comes from
- **THEN** the data folder names palmerpenguins, its authors and CC0
