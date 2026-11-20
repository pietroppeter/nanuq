## ADDED Requirements

### Requirement: Review mode
Every page rendered with the Nanuq theme SHALL have the review mode of `docs/review.nim`
(from tabelline, until nimib has it), unless the page passes `review = false`: a version
line in the masthead (*Version N · updated D*, N being the commits that touched the
page's source) with **✎ Review**, which opens a mode where the reader selects text,
comments on it, and exports the comments as Markdown with a YAML block (`nimib-review`
format) naming the page, its source, its version and commit. The page SHALL stay
readable at phone width in both modes, light and dark.

#### Scenario: Reviewing a post on a phone
- **WHEN** a reader opens a post on a phone, taps **✎ Review**, selects a sentence and writes a note
- **THEN** the sentence is marked, the note is kept in the browser, and **Export** gives a text
  naming the post's source (`docs/blog/<post>.nim`), its version and the quoted sentence

#### Scenario: A new commit
- **WHEN** a commit changes a post's source and the site is built again
- **THEN** the post's version goes up by one, and its comments start empty

### Requirement: Source files
A page that mentions source files of the repository SHALL fold them (whole, or the part it
discusses) in a "Source files" section at its end, made with `nbSourceFiles` and
`nbFoldCode` (from tabelline): each under its path or a title, with its number of lines.
The top of the page SHALL point to the section, every file name shown as code in the text
SHALL link to its fold, and following such a link SHALL open the fold.

#### Scenario: Reading a file a post names
- **WHEN** a reader taps `ffi.nim` in the text of a post
- **THEN** the page goes to the fold of `src/nanuq/ffi.nim` in "Source files", opened
