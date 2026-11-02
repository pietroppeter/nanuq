# Working on Nanuq

Notes for coding agents (and people) changing this repository. How the code is built
and laid out is in README.md and `openspec/specs`; this file only holds the working
rules that are easy to miss.

## Pull requests

- Keep the PR description in sync with the branch. Whenever a push changes what the
  PR does (a new feature, a dropped one, new numbers), update the description and, if
  needed, the title in the same step as the push.

## Changes and ideas

- Ideas and possible next steps go in BACKLOG.md, not straight into work.
- Picked-up work becomes an OpenSpec change (`openspec/changes/`); `openspec/config.yaml`
  has the rules for proposals, specs and archiving. Every proposal lists its differences
  from Polars' Rust and Python APIs, and names follow Polars in camelCase.
- When a change is archived, remove its BACKLOG.md entry and add a CHANGELOG.md line
  under Unreleased with the PR number.

## Tests and docs

- `nim r tests/all.nim` runs the whole suite (tests and spec examples) as one program,
  and `nim r docs/all.nim` renders the whole site. While working on one file, run that
  file (`nim r tests/test_csv.nim`, `nim r docs/blog/move_37.nim`): it compiles faster.
- A new dev-log post needs an entry in `docs/devlog.nim` and a line in README.md.
