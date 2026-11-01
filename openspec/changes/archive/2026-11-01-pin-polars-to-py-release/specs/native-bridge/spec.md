# Spec Delta

## ADDED Requirements

### Requirement: Polars version matches a py-polars release
The `nanuq_ffi` crate SHALL depend on Polars by the git tag of a py-polars release (`py-X.Y.Z`), the same version the Nanuq Book and the explainers use as their Python oracle, with the `[patch.crates-io]` entries of Polars' workspace at that tag; release builds SHALL use that tag's Rust toolchain. Moving to a new py-polars release SHALL move the tag, the patches, the toolchain and the Python oracle together.

#### Scenario: Same results as Python
- **WHEN** a book chapter runs the same query in Nanuq and in the pinned py-polars
- **THEN** the outputs agree, including SQL table functions and seeded `hash`/`sample`
