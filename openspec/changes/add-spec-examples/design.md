# Design

## Where examples go

Inside each requirement, after the SHALL text and before the first scenario. Tested
with the OpenSpec CLI (1.16):

- `openspec validate` passes, and fences are parsed as code: a `### Requirement:` line
  inside a fence does not start a requirement.
- The code does not count towards the "requirement text too long" warning.
- Archive keeps fenced blocks in ADDED and MODIFIED requirements, so a change that alters
  behavior restates and updates the example in its delta, and specview shows that diff.

A spec-level `## Examples` section also validates and survives archive, but deltas can
never change it, so it would drift. Rejected.

## Format

````markdown
```nim
let df = newDataFrame(series("a", [1, 2, 3]))
echo df.select(col("a").isIn([1, 3]))
```

```text
shape: (3, 1)
...
```
````

- `nanuq`, `nanuq/datasets` and `std/[options, os, strutils]` are imported implicitly;
  an example's own `import` lines (e.g. `nanuq/datamancer`) are hoisted.
- Each example is self-contained: tiny frames built inline, or `penguins()`. Files go in
  `getTempDir()`.
- `echo` a frame when the shape or dtypes matter; `echo` `toSeq`, `columns` or `shape`
  when only values do. Full Polars tables are kept (decided by Pietro).
- A ```` ```nim ```` block with no text block after it is compiled and run, but its
  output is not compared.

## The checker

`tools/specexamples.nim` builds one program per spec: each example inside a `block:`,
preceded by an `echo` of a marker, so one compile covers a spec and the output splits
back per example. The 46 examples take about 90 seconds locally. Extra `-d:` flags are
passed to the compile (CI uses `-d:nanuqNoCargo`). `--update` writes the actual output
into the text blocks; the diff is then reviewed like any other change.

Only `openspec/specs/` is checked. A proposal's examples describe future API, so they
cannot run; their outputs are written by hand and corrected with `--update` when the
change is implemented and archived.

## CI trigger

`paths-ignore` cannot re-include a path, and `**.md` matches every spec. `ci.yml`
switches to `paths` with negated patterns, where the last matching pattern wins:
`"**"`, then `"!**.md"`, `"!openspec/**"`, ..., then `"openspec/specs/**"`. The Rust
library is cached, so a spec-only change costs a test run.
