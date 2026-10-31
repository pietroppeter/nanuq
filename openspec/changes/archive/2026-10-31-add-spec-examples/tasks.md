# Tasks

## 1. Checker

- [x] 1.1 Add `tools/specexamples.nim` (run, compare, `--update`, capability filter, pass-through `-d:` flags) and the `nimble specexamples` task
- [x] 1.2 Make `tools/specview.nim` fence-aware when parsing specs, and style ```` ```text ```` blocks as output

## 2. Examples

- [x] 2.1 Add an example to every API requirement of the 11 API specs and fill outputs with `--update`
- [x] 2.2 Review every output against the requirement and its scenarios

## 3. CI and conventions

- [x] 3.1 Switch `ci.yml` to `paths` with negations so `openspec/specs/**` triggers CI, and run `nimble specexamples` in the test job
- [x] 3.2 Add the example rule for spec deltas to `openspec/config.yaml`
- [x] 3.3 Archive the change; add a CHANGELOG line
