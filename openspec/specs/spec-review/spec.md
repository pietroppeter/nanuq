# spec-review Specification

## Purpose
What the specview review page (`tools/specview.nim`) shows.

## Requirements

### Requirement: Full specs in specview
specview SHALL render every spec in `openspec/specs/` in full, with its purpose,
requirements, examples and scenarios, and SHALL mark the specs that an open change
modifies or that changed since `--base`.

#### Scenario: Reading a spec
- **WHEN** a reviewer opens the Specs section and expands `temporal`
- **THEN** every requirement of `openspec/specs/temporal/spec.md` is shown with its example and scenarios

### Requirement: Archived changes are hidden by default
specview SHALL hide archived changes until the reader ticks "Show archived changes",
except archived changes that changed since `--base`. A link to a hidden change SHALL
reveal it.

#### Scenario: No base
- **WHEN** specview runs without `--base` on a repository whose changes are all archived
- **THEN** no change is shown until the checkbox is ticked

#### Scenario: A PR that archives changes
- **WHEN** specview runs with `--base:origin/main` on a branch that archived three changes
- **THEN** those three changes are shown and the other archived ones are hidden
