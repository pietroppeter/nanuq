# Tasks

## 1. Module

- [x] 1.1 Add `src/nanuq/datamancer.nim` (importing `pkg/datamancer`) with `toDatamancer`, using `toSeq` for null-free columns and `Option` reads for columns with nulls; verify with tests for dtypes, column order and nulls
- [x] 1.2 Add `fromDatamancer`, handling int, float, bool, string, constant and object columns; verify with tests for a round trip and a mixed object column
- [x] 1.3 Add `tests/test_datamancer.nim` to `nimble test` and install Datamancer in the CI test job; verify `nimble test` passes, and that the other tests still compile without Datamancer installed

## 2. Docs

- [x] 2.1 Rewrite the conversion in "Plotting with ggplotnim" with `toDatamancer` (keeping the explanation of the copy and of nulls); verify the post renders and republish its artifact
- [x] 2.2 Mention `nanuq/datamancer` in the README
- [x] 2.3 Check CI is green on the PR

## Workflow follow-up

- Archive the change: remove "Datamancer interop both ways" from BACKLOG.md and add a CHANGELOG line.
