# spec-examples Specification

## Purpose
Runnable Nim examples in the OpenSpec specs: where they go, how they are checked
against the code, and how specview shows them.

## Requirements

### Requirement: API requirements have examples
Every requirement in `openspec/specs/` that describes Nim API SHALL include an example: a
```` ```nim ```` block after the requirement text and before the scenarios, followed by a
```` ```text ```` block with what it prints, as Polars prints it. Examples SHALL show
allowed use; failures stay in scenarios. Requirements about process (CI, releases, the
dev log, the C ABI) need none.

```nim
let df = newDataFrame(series("a", [1, 2, 3]))
echo df.select(col("a").isIn([1, 3]))
```

```text
shape: (3, 1)
┌───────┐
│ a     │
│ ---   │
│ bool  │
╞═══════╡
│ true  │
│ false │
│ true  │
└───────┘
```

#### Scenario: New API requirement
- **WHEN** a change adds or modifies a requirement that describes Nim API
- **THEN** its delta includes the example and the expected output

#### Scenario: Process requirement
- **WHEN** a requirement describes CI or the release process
- **THEN** it has no example

### Requirement: Examples are run
`nimble specexamples` SHALL compile and run every ```` ```nim ```` block in
`openspec/specs/`, with `nanuq`, `nanuq/datasets` and `std/[options, os, strutils]`
imported, and fail when an example does not compile, fails at run time, or prints
something other than its ```` ```text ```` block. With `--update` it SHALL write the
actual output into the text blocks instead. Change deltas SHALL NOT be run.

```sh
nimble specexamples                                      # check every spec
nim r tools/specexamples.nim --update expressions        # refresh one spec's outputs
```

#### Scenario: Output drifts
- **WHEN** a behavior change makes an example print a different table
- **THEN** `nimble specexamples` fails and shows the expected and actual output

#### Scenario: Update
- **WHEN** it runs with `--update`
- **THEN** the text blocks hold the actual output and the run passes

#### Scenario: Proposal with future API
- **WHEN** an open change's delta has an example using API that does not exist yet
- **THEN** the checker ignores it

### Requirement: specview shows examples
specview SHALL keep fenced code in a requirement verbatim, never reading a line inside a
fence as a heading, and SHALL render ```` ```text ```` blocks as output, set apart from
the code.

#### Scenario: Nim comment in an example
- **WHEN** an example has a line starting with `#` or `##`
- **THEN** specview shows it in the code block, and the requirement and its scenarios are unchanged
