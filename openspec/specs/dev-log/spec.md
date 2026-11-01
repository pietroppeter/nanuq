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
index, rendered from the data file `docs/coverage/polars.json`. The data SHALL list
Polars feature groups by area with their Polars names, a status for each Nanuq version
(has it, partly, missing, not planned) and a note naming what is still missing; a
version left out of a row SHALL keep the previous version's status. The page SHALL show
totals per version, counts by area, the groups still open in the newest version by
priority, and the full catalogue. Each release PR SHALL refresh the data for that
release. The page is not a dated post and is not listed among the posts.

#### Scenario: A release adds a version
- **WHEN** a release PR adds version `0.7` to `versions` and sets `"0.7": "done"` on the rows it completes
- **THEN** the page shows a 0.7 column, the rows left unchanged show their 0.6 status under 0.7, and the changed rows are marked as new in 0.7

#### Scenario: Index link
- **WHEN** the site is rendered
- **THEN** the index links to the coverage page, and the page does not appear in the list of posts
