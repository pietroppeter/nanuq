# Proposal

## Why

Pietro reviews the dev-log posts and explainers from his phone, and so far every remark
went into a chat message that had to say where on the page it was. tabelline, his other
nimib project, has a review mode for its pages (`docs/review.nim`, not yet in nimib): a
reader opens it with **✎ Review**, selects text, comments on it, and exports every comment
as one text (Markdown with a YAML block naming the page, its source and the version read)
that a coding agent applies to the page's source. Pietro asked (2026-11-19) for it on every
nimib page of Nanuq, nanuq-more and the Nanuq book.

He also asked for tabelline's folded code (`nbFoldCode`): the posts name source files
(`ffi.nim`, `benchmarks/arrow_views.nim`, an explainer's Python twin) that a reader can only
find on GitHub. tabelline folds each piece of code a page talks about under its name and
its length, in a section the page points to.

## What Changes

- `docs/review.nim` and `docs/review.js`: tabelline's review mode, copied as they are (the
  version with review rounds, tabelline#102), without tabelline's notebook-look styles.
  They are meant to move to nimib; until then this copy follows tabelline's.
- `useNanuqTheme` turns the review mode on for every page that uses the theme (all posts,
  the index, the coverage map, the OpenSpec page, and nanuq-more's pages, which use the
  same theme), with `review = false` to leave it off. The version line (*Version 8 ·
  updated 2 Nov 2026*) and **✎ Review** sit in the masthead under the meta line; the
  review mode's colours come from the pack-ice palette, light and dark.
- `docs/foldcode.nim`: `nbFoldCode` (a file, or a part of it between `start` and `stop`,
  folded under its path or a title and its length) and `nbSourceFiles`, a "Source files"
  section at the end of a page. The theme says under the title that the section is there,
  links every file name the text shows as code (`ffi.nim`, `src/nanuq/ffi.nim`) to its
  fold, and a link to a fold opens it. Every post that mentions a file of this repository
  gets the section; the explainers' links to their Python twins, figures and data scripts
  on GitHub now lead to their folds. Files of other repositories stay links.
- The version of a page is the number of commits that touched its source, read from git
  when the page is built; the docs job already checks out the whole history.

## Capabilities

### Modified Capabilities
- `dev-log`: every page of the site has the review mode; pages that mention source files
  fold them in a "Source files" section.

## Differences from Polars

None: this changes the documentation site, not the API.

## Impact

- New `docs/review.nim`, `docs/review.js`, `docs/foldcode.nim`; `docs/nanuqtheme.nim`;
  the eleven pages that mention source files (ten posts and the OpenSpec page).
- Each page carries the review script inline (about 30 KB), so a page stays one file and
  works as a Claude artifact too.
- Comments live in the reader's browser (localStorage), keyed by page and version.
