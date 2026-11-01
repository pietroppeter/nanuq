## ADDED Requirements

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
