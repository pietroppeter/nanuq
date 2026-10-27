# Spec Delta

## RENAMED Requirements
- FROM: `### Requirement: Build Rust only when rust/ changes`
- TO: `### Requirement: Build Rust only when the crate changes`

## MODIFIED Requirements

### Requirement: Build Rust only when the crate changes
CI SHALL build `libnanuq_ffi.a` in a single job whose cache key is a hash of the crate
sources in `src/rust/`, and SHALL share the library with the other jobs, which compile
with `-d:nanuqNoCargo`.

#### Scenario: Change that does not touch rust/
- **WHEN** a push changes only Nim code or docs
- **THEN** the library comes from cache and no Rust toolchain or cargo build runs

#### Scenario: Change to rust/
- **WHEN** a push changes files in `src/rust/`
- **THEN** the library is rebuilt, reusing cached compiled dependencies

## ADDED Requirements

### Requirement: Lib version follows the crate sources
CI SHALL fail when the crate sources differ from those at the tag `lib-v<version>` for
the version in `Cargo.toml`, unless that version ends in `-dev`.

#### Scenario: Rust change without a version bump
- **WHEN** a pull request changes `src/rust/src/lib.rs` and `Cargo.toml` still says
  `0.1.0`, which has a `lib-v0.1.0` tag
- **THEN** CI fails and says to set the version to the next `-dev` version
