## ADDED Requirements

### Requirement: OpenSpec page
The site SHALL publish an OpenSpec page at `openspec.html`, linked from the index, the
coverage page and the README's "How development works", rendered by
`tools/specview.nim` with the dev log's header and footer: every change (archived ones
hidden until the reader asks for them) and every spec in `openspec/specs/` in full. The
page is rebuilt from the repository each time the site is, so it shows the specs and
changes on `main`. It is not a dated post and is not listed among the posts.

#### Scenario: A change is archived
- **WHEN** a pull request that archives a change into `openspec/specs/` is merged
- **THEN** the published OpenSpec page shows the updated spec and lists the change as archived

#### Scenario: Index link
- **WHEN** the site is rendered
- **THEN** the index links to the OpenSpec page, and the page does not appear in the list of posts
