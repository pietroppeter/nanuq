## MODIFIED Requirements

### Requirement: Tests, example and dev log
CI SHALL run the test suite, which includes the spec examples, as one program
(`tests/all.nim`), and the example, and render the site as one program (`docs/all.nim`):
the nimib dev-log posts in `docs/blog`, then the index page `docs/index.nim` and the
living pages (the Polars coverage page and the OpenSpec page). On `main`, after
these succeed, it SHALL deploy them to GitHub Pages, with the index as the site root.

#### Scenario: Merge to main
- **WHEN** a commit lands on `main` and the test and docs jobs pass
- **THEN** the dev log and the living pages are deployed to GitHub Pages, and the site root lists the posts

#### Scenario: Stale spec example
- **WHEN** a pull request changes behavior that a spec example shows
- **THEN** the test job fails until the example's output is updated

#### Scenario: New test file
- **WHEN** a pull request adds `tests/test_x.nim`
- **THEN** the test job runs it as part of `tests/all.nim`, with no list to update

## ADDED Requirements

### Requirement: Fast linking
Builds in the repository SHALL link with lld, without debug info, on Linux when `ld.lld`
is installed, unless `-d:nanuqKeepDebugInfo` is given. CI SHALL make sure lld is
installed.

#### Scenario: Linking a test program
- **WHEN** CI links a program against the static Polars library
- **THEN** it uses lld and the link takes about a second, not about nine
