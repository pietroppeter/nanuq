## MODIFIED Requirements

### Requirement: Examples are run
Every ```` ```nim ```` block in `openspec/specs/` SHALL be a unittest test of the test
suite (`tests/test_specs*.nim`, named `<capability>:<line>`), with `nanuq`,
`nanuq/datasets` and `std/[options, os, strutils]` imported, that fails when the
example does not compile, fails at run time, or prints something other than its
```` ```text ```` block. Specs that import other packages SHALL be in test files of
their own. `nimble specexamples` SHALL check the same examples, and with `--update`
write the actual output into the text blocks instead. Change deltas SHALL NOT be run.

```sh
nim r tests/test_specs.nim "spec expressions::*"         # check one spec
nimble specexamples                                      # check every spec
nim r tools/specexamples.nim --update expressions        # refresh one spec's outputs
```

#### Scenario: Output drifts
- **WHEN** a behavior change makes an example print a different table
- **THEN** the test suite fails and shows the expected and actual output

#### Scenario: Update
- **WHEN** it runs with `--update`
- **THEN** the text blocks hold the actual output and the run passes

#### Scenario: Proposal with future API
- **WHEN** an open change's delta has an example using API that does not exist yet
- **THEN** the checker ignores it
