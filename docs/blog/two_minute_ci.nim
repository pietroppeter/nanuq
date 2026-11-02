import nimib
import ../nanuqtheme

nbInit
nb.useDevlogPost("two-minute-ci",
  epigraph = "Fifteen minutes of CI, and most of it went into linking the same 310 MB library ninety-two times.")

nbText: """
By Nanuq 0.6 a CI run took about fifteen minutes, and it got longer with every release.
None of that time went into anything heavy: the Rust library comes from a cache or a
release, the explainers read committed data, and the benchmark chapters of the book
read result files. The time went into the toolchain doing the same work over and over.
Two changes brought a run down to about two and a half minutes: one program per suite
instead of one binary per file, and a faster linker. This post shows where the time
went, what changed, and what it costs. It is also a note for anyone wrapping a big
static library for Nim: link time is the first thing to measure.

## Where fifteen minutes went

Every test file, every spec's examples and every page of this site was its own binary.
Each one compiled Nanuq again and linked `libnanuq_ffi.a`, the static Polars wrapper,
which is about 310 MB. With GNU ld that link takes about 9 seconds of a 12-second
compile, every time. Main run #175 (2 November) broke down like this:

| Job | Step | Time | Programs |
| --- | --- | --- | --- |
| test | the test files, `nim r` each | 6m45s | 45 |
| test | the spec examples, one program per spec | 5m56s | 47 |
| test | `nimble install`, the moto venv | 1m05s | |
| docs | the pages, `nim r` each | 2m57s | 16 |
| docs | `nimble install` (nimib, ggplotnim, plotly) | 1m26s | |

The book had the same shape: about fifty chapters, one binary each, and a full build
(every Nanuq pin bump) took 6m54s. Its pull requests were already fast, because since
[book PR #5](https://github.com/pietroppeter/nanuq-book/pull/5) only the chapters whose
inputs changed are rebuilt.

## The linker

Timing the link of one test binary by itself, with the same objects each time:

| Linker | Time |
| --- | --- |
| GNU ld (default) | 9.2 s |
| GNU ld, `--strip-debug` | 8.6 s |
| gold | 3.2 s |
| lld | 3.3 s |
| gold, `--strip-debug` | 3.9 s |
| lld, `--strip-debug` | 0.7 s |

`config.nims` now passes `-fuse-ld=lld -Wl,--strip-debug` on Linux when `ld.lld` is
installed, and CI makes sure it is. That alone took the
45 test files from 9m32s to 4m22s on a 4-core machine. It only affects builds in this
repository: `config.nims` doesn't ship with the package, so users of Nanuq link as
before.

## One program per suite

The bigger win came from not building 45 programs at all. Nim runs the top-level code
of every imported module when the program starts, in import order. So a module that
imports every test file runs every unittest suite, one after the other, and none of
the test files has to change. `tests/all.nim` finds them at compile time (simplified):

```nim
macro importTests(): untyped =
  let dir = currentSourcePath().parentDir
  var src = ""
  for name in sortedTestNames(dir):  # tests/test_*.nim, from `ls`
    # absolute: parseStmt has no file to be relative to
    src.add "import \"" & dir / name & "\"\n"
  result = parseStmt(src)

importTests()
```

Files that need an optional package (Datamancer, Arraymancer, db_connector) go in only
when `(compiles do: import datamancer)` holds, the same check nimib's `moduleAvailable`
uses. A single file still runs on its own, as `nim r tests/test_csv.nim`, and unittest
filters work on the whole suite: `nim r tests/all.nim "csv::*"`.

The same trick renders this site. `docs/all.nim` imports every post, then the index,
the coverage map and the OpenSpec page. Each page renders when its module is
initialised, and all 16 came out byte-identical to the page-by-page build. One thing
did need care: display options are global, and four posts call `setConfig`. So
`useDevlogPost` now starts every post with `resetConfig()`.

The spec examples went one step further, and became tests. `tests/specsuite.nim` reads
`openspec/specs/*/spec.md` at compile time and turns every example into a unittest
test named after its spec and line. What the example prints is captured at the file
descriptor, so output from the Rust side counts too, and it is compared with the
example's text block. The examples were always meant to be guaranteed to work. Now they
fail like any other test. Specs that import Arraymancer or Datamancer get files of their
own, because their names clash with the others' (`quantile` is defined in both).

## The numbers

Measured locally (4 cores, cold cache) and on pull request runs of
[nanuq#67](https://github.com/pietroppeter/nanuq/pull/67):

| What | Before | After |
| --- | --- | --- |
| tests, 45 files (local) | 9m32s | 47 s |
| spec examples, 224 (local) | 6m00s | 35 s |
| tests + spec examples, 684 tests (local) | 15m32s | 70 s |
| site, 16 pages (local) | 4m46s | 1m25s |
| CI test job | 14m05s | 1m16s |
| CI docs job (`~/.nimble` now cached too) | 4m45s | 1m47s |
| book full build (lld only) | 6m54s | 5m29s |

The book gained less. Its chapters also run Python (the other half of each tab) and
are traced with strace to record which files they read, so linking is a smaller share
of their time. Building the chapters as one program would also merge their traces.
That is a separate design, for later.

## What it costs

Two things.

**The edit loop.** Changing one test file now recompiles the whole suite, about 26
seconds, against about 12 seconds for one file on its own. When working on one file,
run that file.

**Debug info.** `--strip-debug` drops the DWARF sections of the binary, almost all of
which belong to the Polars library. What stays: Nim's own stack traces, which don't use
DWARF, and the symbol table, so a Rust panic backtrace still names its functions. What
goes: file and line numbers in those backtraces, and stepping through Polars source in
gdb or lldb. We have not needed either yet. When we do, `-d:nanuqKeepDebugInfo` brings
them back for that build. It is the right trade for a test suite that is built far
more often than it is debugged.
"""

nbSave
