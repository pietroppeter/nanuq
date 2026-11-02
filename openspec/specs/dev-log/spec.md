# dev-log Specification

## Purpose
The Nanuq dev log: dated nimib posts in `docs/blog`, an index page, and the Nanuq theme
they share. It is published with GitHub Pages and is separate from the official
documentation that will come later.

## Requirements

### Requirement: Index of posts
The site root SHALL be an index page listing every rendered post in `docs/blog`, newest
first, each with its date, title, one-line summary and a link to the post. Adding a post
SHALL NOT require editing the index.

#### Scenario: New post
- **WHEN** a post `docs/blog/x.nim` writing `2026-11-02-x.html` is added and CI renders the site
- **THEN** the index lists it first, dated 2 November 2026, with its title and summary

#### Scenario: Post without a summary
- **WHEN** a post does not set a summary
- **THEN** the index still lists it, with date and title only

### Requirement: Dated post files
Each post SHALL render to a file in `docs/blog` named `YYYY-MM-DD-<slug>.html`, and its
URL SHALL stay the same once published.

#### Scenario: Existing links
- **WHEN** the index is introduced
- **THEN** the existing post URLs under `blog/` keep working

### Requirement: Polars coverage page
The site SHALL publish a Polars coverage page at `polars_coverage.html`, linked from the
index and the README, rendered from the data file `docs/coverage/polars.json`. The page
SHALL describe the latest Nanuq release only: the data names that release and lists
Polars feature groups by area with their Polars names, a status (has it, partly,
missing, not planned), a note naming what is still missing, a priority for open groups,
and a mark on the groups whose status changed in that release. When the next release has
a plan, the data MAY name it and mark the open groups it plans; the page SHALL then show
them. The page SHALL show the release totals, counts by area, the open groups by priority
and the full catalogue, with the dev log's header and footer. Each release PR SHALL
refresh the data for that release. The page is not a dated post and is not listed among
the posts.

#### Scenario: A release refreshes the data
- **WHEN** the 0.7 release PR sets the release to 0.7, clears the old new-marks, and updates and marks the rows that 0.7 changed
- **THEN** the page shows only 0.7 statuses, with the changed groups marked as new in 0.7

#### Scenario: No plan for the next release
- **WHEN** the data names no next release
- **THEN** the page shows no Planned column

#### Scenario: Index link
- **WHEN** the site is rendered
- **THEN** the index links to the coverage page, and the page does not appear in the list of posts

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
