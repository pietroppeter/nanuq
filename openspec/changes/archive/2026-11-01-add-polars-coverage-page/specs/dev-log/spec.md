## ADDED Requirements

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
