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
