# Proposal

## Why

Scenarios state the rules precisely, but they are hard to read: a WHEN/THEN sentence
describes a call and its result in prose, and the reader has to picture both. A short
piece of Nim and the table it prints shows the same thing at a glance, the way Polars'
own docs do.

Examples that nobody runs go stale, so they must be checked, like tests.

This change comes from a request in the project thread (no BACKLOG.md entry).

## What Changes

- Every requirement that describes Nim API gets an example: a ```` ```nim ```` block
  right after the requirement text and before the scenarios, followed by a
  ```` ```text ```` block with what it prints. Output is shown as Polars prints it,
  full tables included. Examples show what the spec allows; errors stay in scenarios.
- The examples are added to the 11 API specs (api-conventions, column-selectors,
  combining-frames, csv-io, data-types, dataframe-api, datamancer-interop, datasets,
  expressions, frame-verbs, missing-values). The process specs (ci,
  binary-distribution, dev-log, native-bridge) get none.
- New tool `tools/specexamples.nim` (`nimble specexamples`): compiles and runs every
  example in `openspec/specs/`, compares its output with the text block, and with
  `--update` rewrites the text blocks. Change deltas are not run, since they describe
  API that may not exist yet.
- CI runs the checker in the test job, and runs again when `openspec/specs/` changes
  (it no longer skips main specs; the rest of `openspec/` is still skipped).
- specview keeps fenced code verbatim when parsing specs (a Nim comment or a `##` line
  inside a fence is no longer read as a heading), and shows output blocks apart from
  the code.
- A new rule in `openspec/config.yaml` asks every spec delta to give each API
  requirement an example.

## Capabilities

### New Capabilities

- `spec-examples`: runnable examples in the OpenSpec specs, their format, and the
  checker.

### Modified Capabilities

- `ci`: main specs trigger CI again, and CI runs the spec examples.

## Impact

- `openspec/specs/*/spec.md` (examples only, no requirement text changes)
- `tools/specexamples.nim` (new), `tools/specview.nim`, `nanuq.nimble`
- `.github/workflows/ci.yml`, `openspec/config.yaml`
- The specs grow by about 70%, mostly output tables.

## Differences from Polars

None: this change adds no Nim API. The examples follow Polars' docs in showing code with
the printed table under it.
