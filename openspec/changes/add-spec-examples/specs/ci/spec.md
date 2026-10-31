# Spec Delta

## MODIFIED Requirements

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
