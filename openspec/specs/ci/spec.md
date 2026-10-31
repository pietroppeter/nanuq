# ci Specification

## Purpose
Continuous integration and publishing for the repository (`.github/workflows/ci.yml`).

## Requirements

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

### Requirement: Skip CI for non-code changes
CI SHALL NOT run for pushes or pull requests that only change Markdown files, `LICENSE`,
`.gitignore`, `openspec/` or `.claude/`, except `openspec/specs/`, whose examples CI runs.

#### Scenario: OpenSpec-only change
- **WHEN** a pull request only changes files under `openspec/changes/`
- **THEN** no CI run starts

#### Scenario: Main spec change
- **WHEN** a pull request changes `openspec/specs/expressions/spec.md`
- **THEN** CI runs, including the spec examples

#### Scenario: Dev log change
- **WHEN** a change touches `docs/`
- **THEN** CI runs, so the dev log is rebuilt

### Requirement: Tests, example and dev log
CI SHALL run the test suite, the example and the spec examples (`nimble specexamples`),
and render the nimib dev-log posts in `docs/blog` and then the index page
`docs/index.nim`. On `main`, after these succeed, it SHALL deploy the posts and the index
to GitHub Pages, with the index as the site root.

#### Scenario: Merge to main
- **WHEN** a commit lands on `main` and the test and docs jobs pass
- **THEN** the dev log is deployed to GitHub Pages, and the site root lists the posts

#### Scenario: Stale spec example
- **WHEN** a pull request changes behavior that a spec example shows
- **THEN** the test job fails until the example's output is updated

### Requirement: Lib version follows the crate sources
CI SHALL fail when the crate sources differ from those at the tag `lib-v<version>` for
the version in `Cargo.toml`, unless that version ends in `-dev`.

#### Scenario: Rust change without a version bump
- **WHEN** a pull request changes `src/rust/src/lib.rs` and `Cargo.toml` still says
  `0.1.0`, which has a `lib-v0.1.0` tag
- **THEN** CI fails and says to set the version to the next `-dev` version
