# Tasks

## 1. Move the crate and measure

- [x] 1.1 Move `rust/` to `src/rust/` (git mv). Update `ffi.nim`, `nanuq.nimble` tasks, `.gitignore`, `ci.yml` paths and cache keys, `openspec/config.yaml` context, README and the dev-log posts' mentions of `rust/`, and add `skipDirs` for `rust/target`. Verify `nimble test` passes and `nimble install` into a temporary `--nimbleDir` contains `rust/Cargo.toml` but no `rust/target`.
- [ ] 1.2 Measure the archive (`tar czf` of `libnanuq_ffi.a`) with the current profile and with `lto = "fat"`, `codegen-units = 1`. Keep the LTO settings if the archive is clearly smaller and the build stays under ~20 minutes. Record the numbers in the PR description.

## 2. Version in the library

- [x] 2.1 Add `nq_version()` to `src/rust/src/lib.rs` and `ffi.nim`, plus the startup check against the version parsed from `Cargo.toml`. Verify with a test that the versions match, and that a library built with a different crate version stops with an error naming both versions.

## 3. Release workflow

- [ ] 3.1 Add `.github/workflows/release-lib.yml` (on `lib-v*` tags and `workflow_dispatch` without publishing): check the tag against `Cargo.toml`, run the 6-archive build matrix as in design.md (manylinux_2_28 for Linux, macos-15, windows-latest with MinGW, v3 / legacy-cpu for x86_64), smoke-test each archive with `tests/test_basic.nim` on its runner, then publish the release with the sums file and open a PR that updates `src/nanuq/lib-sums.txt`. Verify with a `workflow_dispatch` run that all six jobs build and pass their smoke tests.
- [ ] 3.2 Add the Windows system libraries to `ffi.nim`'s link flags. Verify via the Windows smoke test in 3.1.

## 4. Compile-time download

- [x] 4.1 In `ffi.nim`, add the `nanuqLib` policy (`auto` / `prebuilt` / `source`, with `nanuqNoCargo` as `prebuilt`), the target triple, the lib version from `Cargo.toml`, and reading `lib-sums.txt`. Verify that with `-d:nanuqLib=source` and no local build, cargo runs as before.
- [x] 4.2 Implement the cache lookup, the download (curl), checksum check (sha256sum / shasum / certutil), unpacking with a `.complete` marker (see design.md), and a hint for each source used. Verify against the `workflow_dispatch` archives from 3.1 (served from a local directory, or uploaded to a test pre-release): a clean cache downloads and links, a second compile uses the cache, a corrupted archive stops with the checksum error, and an unknown target falls back to cargo.
- [x] 4.3 Add CPU detection for x86_64 Linux and `-d:nanuqLegacyCpu`. Verify both choices, using a stubbed flags string for the old-CPU case.
- [ ] 4.4 Document installing (nimble, Atlas, git), the defines and the cache location in the README, and update the `ffi.nim` module doc. Verify the README commands work in a clean container without Rust once a release exists (task 6.1).

## 5. CI check

- [x] 5.1 Add a CI step that fails when `src/rust/` differs from tag `lib-v<version>` and the version doesn't end in `-dev`. Verify on a branch with a fake tag: changing `lib.rs` fails the step, and a `-dev` version passes.

## 6. End to end

- [ ] 6.1 After Pietro pushes `lib-v0.1.0` and the sums PR is merged: in a fresh container without Rust, `nimble install` the package from this branch and compile and run the README example. Verify that it finishes in under a minute with a download hint and no cargo hint.

## Workflow follow-up

- Archive the change: remove "Prebuilt binaries for users" and "`nimble install` support" from BACKLOG.md, add CHANGELOG lines, then tag `v0.1.0`.
