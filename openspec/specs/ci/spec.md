# ci Specification

## Purpose
Continuous integration and publishing for the repository (`.github/workflows/ci.yml`).

## Requirements

### Requirement: Build Rust only when rust/ changes
CI SHALL build `libnanuq_ffi.a` in a single job whose cache key is a hash of the
`rust/` sources, and SHALL share the library with the other jobs, which compile with
`-d:nanuqNoCargo`.

#### Scenario: Change that does not touch rust/
- **WHEN** a push changes only Nim code or docs
- **THEN** the library comes from cache and no Rust toolchain or cargo build runs

#### Scenario: Change to rust/
- **WHEN** a push changes files in `rust/`
- **THEN** the library is rebuilt, reusing cached compiled dependencies

### Requirement: Skip CI for non-code changes
CI SHALL NOT run for pushes or pull requests that only change Markdown files, `LICENSE`,
`.gitignore`, `openspec/` or `.claude/`.

#### Scenario: OpenSpec-only change
- **WHEN** a pull request only changes files under `openspec/`
- **THEN** no CI run starts

#### Scenario: Dev log change
- **WHEN** a change touches `docs/`
- **THEN** CI runs, so the dev log is rebuilt

### Requirement: Tests, example and dev log
CI SHALL run the test suite and the example, and render the nimib dev-log posts in
`docs/blog`. On `main`, after these succeed, it SHALL deploy the posts to GitHub Pages,
with the site root opening the latest post.

#### Scenario: Merge to main
- **WHEN** a commit lands on `main` and the test and docs jobs pass
- **THEN** the dev log is deployed to GitHub Pages
