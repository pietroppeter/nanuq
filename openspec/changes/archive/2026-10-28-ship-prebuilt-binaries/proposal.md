# Proposal

## Why

The first compile of a program that imports Nanuq builds Polars from source with cargo,
which takes about ten minutes and needs a Rust toolchain. Before tagging 0.1, users
should be able to `nimble install nanuq` and compile in seconds, on the common platforms,
without Rust.

There is a second problem. `nimble install` copies only `srcDir` (`src/`) into the
package directory, so an installed Nanuq has no `rust/` crate and can't build the library
at all (checked with nimble 0.18.2). Today Nanuq only works from a git checkout.

This takes up the BACKLOG.md entries "Prebuilt binaries for users" and
"`nimble install` support" (Distribution). The research behind it is in the dev-log
post "Shipping the Rust half" (`docs/blog/shipping_rust_binaries.nim`).

## What Changes

- **Release workflow.** Pushing a `lib-v<version>` tag builds `libnanuq_ffi.a` for
  `x86_64-unknown-linux-gnu`, `aarch64-unknown-linux-gnu`, `aarch64-apple-darwin` and
  `x86_64-pc-windows-gnu`. Each x86_64 target also gets a `legacy-cpu` build. The
  archives and their SHA-256 sums are attached to a GitHub Release, and a PR commits the
  sums to the repository. Lib releases are tagged by hand.
- **Compile-time download.** When no library is available locally, importing `nanuq`
  downloads the archive for the target platform once into a per-user cache, verifies
  its checksum and links it. This is the default. A cargo build remains the fallback
  for any platform or version without a prebuilt library.
- **CPU variants, as Explorer does them.** On Linux x86_64 the CPU is checked at compile
  time, and the legacy build is picked if it lacks AVX2/FMA-era features.
  `-d:nanuqLegacyCpu` forces the legacy build everywhere.
- **Lib versioning.** The Rust library has its own version (`rust/Cargo.toml`),
  separate from the Nim package version. A version ending in `-dev` never downloads.
  CI fails if the Rust sources differ from the last released lib while the version
  still claims to be that release.
- **Version check at startup.** The library reports its version, and Nanuq refuses to
  run with a library that doesn't match the version it was compiled for.
- **`nimble install` works.** The Rust crate moves from `rust/` to `src/rust/` so that
  it ships with the installed package, and the source fallback works there too.
- **Policy switch.** `-d:nanuqLib=auto|prebuilt|source` picks where the library comes
  from. `-d:nanuqNoCargo` stays as an alias for `prebuilt`. `-d:nanuqLibDir` is
  unchanged.
- The README gets an install section.

## Capabilities

### New Capabilities
- `binary-distribution`: how prebuilt libraries are built, versioned, published, chosen
  for a platform and CPU, downloaded, verified and cached.

### Modified Capabilities
- `native-bridge`: "Linking the static library" changes. The library can now come from
  the download cache, the policy define is new, the crate lives in `src/rust/`, and the
  library version is checked at runtime.
- `ci`: "Build Rust only when rust/ changes" moves to the new path, and there is a new
  check that lib versions are bumped when the Rust sources change.

## Differences from Polars

The Nim API doesn't change. The differences are in how the native code reaches users:

- **No wheels.** Python Polars ships prebuilt wheels through PyPI at install time. Nanuq
  downloads its prebuilt library from GitHub Releases at compile time, the way Elixir's
  Explorer (rustler_precompiled) and r-polars do. The Rust crate `polars` is always
  built from source by cargo.
- **CPU variants are picked automatically.** Python publishes a separate package for
  old CPUs (`polars-lts-cpu`, now `polars[rtcompat]`) that users have to choose
  themselves. Nanuq picks the legacy build on Linux by checking the CPU, and otherwise
  takes a define.
- **Fewer platforms.** Python wheels cover more targets (Intel macOS, musl, Windows
  MSVC and arm64). Nanuq starts with four, and other platforms build from source.
- **Windows uses MinGW.** The Windows library targets `x86_64-pc-windows-gnu` to link
  with Nim's default C compiler. Python wheels use MSVC.

## Impact

- `rust/` moves to `src/rust/`. This touches `ffi.nim`, `nanuq.nimble` tasks, CI cache
  keys and paths, `.gitignore`, the OpenSpec config context and the docs that mention
  `rust/`.
- `rust/src/lib.rs` gains `nq_version()`, declared in `ffi.nim`. This rebuilds the
  library once in CI.
- New `.github/workflows/release-lib.yml` and a committed sums file under `src/nanuq/`.
- `src/nanuq/ffi.nim`: the source order, download, checksum, cache and CPU detection,
  all at compile time. The tools needed at compile time are `curl` and `tar` (present on
  Windows 10+, macOS and mainstream Linux) and the platform's SHA-256 tool.
- Contributors working from a git checkout with a built `target/` see no change.
