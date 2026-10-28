# Spec Delta

## MODIFIED Requirements

### Requirement: Tests, example and dev log
CI SHALL run the test suite and the example, and render the nimib dev-log posts in
`docs/blog` and then the index page `docs/index.nim`. On `main`, after these succeed, it
SHALL deploy the posts and the index to GitHub Pages, with the index as the site root.

#### Scenario: Merge to main
- **WHEN** a commit lands on `main` and the test and docs jobs pass
- **THEN** the dev log is deployed to GitHub Pages, and the site root lists the posts
