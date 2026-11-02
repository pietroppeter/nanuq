# Proposal

## Why

CI took about 15 minutes a run, and almost all of it was the same work repeated. Every
test file (45), every spec's examples (47) and every dev-log page (16) was compiled
into its own binary, and each binary links the static Polars library (~310 MB): about
9 s of GNU ld per binary, on top of compiling Nanuq again each time. On main run #175
the test job took 14 min (tests 6m45s, spec examples 5m56s) and the docs job 4m45s
(nimble install 1m26s, rendering 2m57s). Pietro asked (2026-11-02) for a single test
runner and a single doc runner, able to run one file or all, and for times that
actually go down.

## What Changes

- `tests/all.nim` runs every `tests/test_*.nim` in one program. It finds them at compile
  time, so there is no list to keep. The files that need an optional package
  (Datamancer, Arraymancer, db_connector) are left out when it is missing. A single file
  still runs on its own, and unittest filters work.
- The spec examples become unittest tests. `tests/specsuite.nim` reads
  `openspec/specs/*/spec.md` at compile time and turns each example into a test named
  `<capability>:<line>`. Its output is captured at the file descriptor and compared
  with the text block. `tests/test_specs.nim` holds the specs that need no other
  package. The Arraymancer, Datamancer and SQLite specs get their own files, because
  their imports clash with the rest (`quantile`). `tools/specexamples.nim` keeps
  `--update`, and now also builds one program instead of one per spec.
- `docs/all.nim` renders the whole site in one program: the posts in file-name order,
  then the index, the coverage map and the OpenSpec page. Each page renders when its
  module is initialised, so the posts do not change, and each still renders on its
  own. `useDevlogPost` calls `resetConfig()`, so one post's display options cannot
  reach the next.
- `config.nims` links with lld and leaves out the library's debug info
  (`-fuse-ld=lld -Wl,--strip-debug`) on Linux when `ld.lld` is installed. This takes a
  link from 9.2 s to 0.7 s. `-d:nanuqKeepDebugInfo` turns it off. Nim's stack traces
  do not use DWARF.
- CI uses the runners, drops the separate spec-examples step, and caches `~/.nimble`
  (test and docs jobs) and the moto venv. `nimble test` and `nimble docs` use the
  runners.

## Capabilities

### Modified Capabilities
- `ci`: tests, spec examples and the site each build as one program; fast linking.
- `spec-examples`: the examples run as unittest tests in the test suite.

## Differences from Polars

None: this changes how Nanuq is tested and built, not its API.

## Impact

- New `tests/all.nim`, `tests/specsuite.nim`, `tests/test_specs*.nim`, `docs/all.nim`.
- `tools/specexamples.nim` (one program, exports its parser), `docs/nanuqtheme.nim`,
  `config.nims`, `nanuq.nimble`, `.github/workflows/ci.yml`.
- Measured: test job 14m05s → 2m21s and docs job 4m45s → 2m55s on the first PR run,
  before caching. Locally, on 4 cores with a cold cache: tests 9m32s → 47 s, spec
  examples 6m00s → 35 s, docs 4m46s → 1m25s with byte-identical HTML.
- Editing one test file now recompiles the whole suite (~26 s), not one file (~12 s).
  When iterating on one file, run it on its own.
- Partly covers the backlog entry "Cache rendered dev-log posts in CI". Installs are
  cached and rendering is one program, but every post is still re-rendered.
