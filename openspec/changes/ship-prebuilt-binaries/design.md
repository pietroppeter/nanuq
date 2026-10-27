# Design

## Context

`src/nanuq/ffi.nim` finds `libnanuq_ffi.a` at compile time: `-d:nanuqLibDir`, else
`rust/target/release`, else it runs `cargo build` through `gorgeEx`. CI already builds
the library once per change of the crate and passes it to the other jobs.

`nimble install` copies only `srcDir`, and `installDirs` is resolved inside `srcDir`, so
there is no way to ship a top-level `rust/` with the package (both checked with nimble
0.18.2). Atlas and nimby clone the whole repository but don't run nimble hooks.

The research and the comparison with other ecosystems are in the dev-log post
`docs/blog/shipping_rust_binaries.nim`. The requirements are in
`specs/binary-distribution`, `specs/native-bridge` and `specs/ci`.

## Goals / Non-Goals

**Goals:**
- A user on one of the four platforms compiles a first Nanuq program in seconds,
  without Rust, whether Nanuq came from nimble, Atlas, nimby or a git clone.
- Contributors who build the crate locally see no change.
- A binary that doesn't match the sources is never linked silently.

**Non-Goals:**
- A shared library option (it stays in the backlog).
- Intel macOS, musl, Windows MSVC or Windows arm64 builds.
- Automatic lib releases. Tags are pushed by hand.
- Signing the archives. The committed checksums are the trust anchor.

## Decisions

### The crate moves to `src/rust/`
This is the only layout nimble installs. `ffi.nim` finds the crate as
`currentSourcePath.parentDir.parentDir / "rust"`, which is `src/rust` in a checkout and
`<pkg>/rust` in an installed package. Alternatives considered:
- *Drop `srcDir`.* This moves every Nim module and changes import paths for tests and
  docs.
- *No source fallback for installed packages.* Users on other platforms would have to
  clone the repository.

`nanuq.nimble` adds `skipDirs` for `rust/target` so that a local `nimble install` from a
checkout doesn't copy gigabytes of build output.

### Lib version comes from Cargo.toml; sums come from a committed file
`ffi.nim` reads the crate version from `src/rust/Cargo.toml` with `staticRead`.
`src/nanuq/lib-sums.txt` holds the `lib-v` version it was generated for and one
`<sha256>  <archive>` line per archive, in `sha256sum` format. A download happens only
when the two versions are equal and the version doesn't end in `-dev`. The release
workflow generates the file, and a bot PR commits it. Between a version bump and the
release the versions differ, so the library builds from source, which is the right
behaviour for unreleased Rust code.

Alternative: one Nim constant per target in a `.nim` file. That's harder to diff
against the release's sums file.

### Download with curl, tar and the system SHA-256 tool, at compile time
Everything runs through `gorgeEx` during compilation:
`curl -fsSL --retry 2 -o <tmp> <url>`, then the platform hash tool (`sha256sum`,
`shasum -a 256` or `certutil -hashfile <f> SHA256`), then `tar -xzf` into the cache
directory, finally renaming a temporary directory into place so that two compiles
running at once never see half a file. Hashing a 100 MB archive in the Nim VM would take
too long.

Cache root: `$XDG_CACHE_HOME` or `~/.cache` on Linux, `~/Library/Caches` on macOS,
`%LOCALAPPDATA%` on Windows, each plus `nanuq/<libver>/<target>/`. `-d:nanuqCacheDir`
overrides it.

Alternative: a nimble `before install` hook. Atlas, nimby, submodules and
`nimble develop` don't run it, so it could only warm the cache, which isn't worth a
second code path.

### Target triple from Nim's target defines
The triple comes from `hostOS`/`hostCPU` as seen by the compiler for the *target*
(`defined(linux)`, `defined(amd64)` and so on). So cross-compiling with `--os`/`--cpu`
picks the archive for the target. CPU feature detection runs only when the target is
x86_64 Linux and the compiler itself runs on x86_64 Linux. It reads the flags line of
`/proc/cpuinfo` and requires `avx avx2 bmi1 bmi2 fma f16c movbe` (the x86-64-v3 set as
listed there).

### Building portable archives
- **Linux** is built inside the `manylinux_2_28` container for each architecture. A
  static lib compiled on a glibc 2.39 runner can reference newer symbols from C
  dependencies (for example the `__isoc23_*` redirects), which would fail to link on
  older systems.
- **macOS** is built on `macos-15` with `MACOSX_DEPLOYMENT_TARGET=11.0`.
- **Windows** is built on `windows-latest` with the MinGW toolchain that is preinstalled
  there.
- **Modern x86_64** builds use `RUSTFLAGS=-C target-cpu=x86-64-v3`, and legacy-cpu
  builds use no CPU flags.
- **Release profile:** `lto = "fat"` and `codegen-units = 1` if they make the archive
  smaller without making the build too slow. This is measured in the first task.

Every job smoke-tests its archive by running `tests/test_basic.nim` with
`-d:nanuqLibDir` on its own runner. The Windows job runs the test under the default
MinGW compiler, and `ffi.nim` gains the Windows system libraries Rust needs (`ws2_32`,
`userenv`, `bcrypt`, `ntdll`).

### Runtime version check
`nq_version()` returns `CARGO_PKG_VERSION` as a static C string. The top level of
`ffi.nim` compares it with the compile-time version and raises a `Defect` with both
versions in the message.

### Policy define
`const nanuqLib {.strdefine.} = "auto"`. `nanuqNoCargo` maps to `prebuilt`. Every
branch emits a `{.hint.}` naming the source it used, and a `{.error.}` lists the ways
out (install Rust, pass `-d:nanuqLibDir`, check the network).

## Risks / Trade-offs

- **[Corporate proxies block the download]** `curl` honours `HTTPS_PROXY`. A failed
  download falls back to cargo under `auto`, and the hint names the URL so the archive
  can be fetched by hand and passed with `-d:nanuqLibDir`.
- **[Release asset deleted or renamed]** The download fails and the library builds from
  source. Assets are never replaced: a fix ships as a new lib version.
- **[A cargo build inside the installed package dir]** writes `target/` into
  `pkgs2/`. Nimble doesn't re-verify package checksums after install. If that turns
  out to matter, the fallback can use the cache as `--target-dir`.
- **[Archive size]** About 300 MB unstripped before compression. GitHub allows 2 GiB per
  asset. It's measured in task 1, and LTO is applied if it helps.
- **[`/proc/cpuinfo` misses a flag on some kernels]** The legacy build is picked, which
  is slower but safe. `-d:nanuqLegacyCpu` is the manual override.

## Migration Plan

1. Merge the implementation, with the crate at `src/rust/` and version `0.1.0`. Main
   builds from source until the first lib release, as it does today.
2. Pietro pushes `lib-v0.1.0`. The workflow publishes the release and opens the sums PR.
   Merging it turns on downloads for `0.1.0`.
3. Pietro tags the package `v0.1.0`.

Rollback: delete `src/nanuq/lib-sums.txt` (or empty it), and every compile builds from
source as before.
