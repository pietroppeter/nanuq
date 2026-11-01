# Spec Delta

## ADDED Requirements

### Requirement: Release build configuration
Release archives SHALL be built with a pinned nightly Rust toolchain and the crate
features `nightly` (Polars' nightly feature) and `jemalloc` (jemalloc as Rust's global
allocator), except on Windows, where only `nightly` is used. Both features SHALL be off
by default, so that a local build needs only stable Rust.

#### Scenario: Local build
- **WHEN** a contributor runs `nimble buildRust` with stable Rust
- **THEN** the library builds without either feature, and everything except `str.toTitlecase` works

#### Scenario: Release smoke test
- **WHEN** a release archive is smoke-tested
- **THEN** `str.toTitlecase` works with it
