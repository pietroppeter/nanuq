# Spec Delta

## Purpose
How users get a prebuilt `libnanuq_ffi` instead of compiling Polars: how libraries are
built, versioned and published, and how a compile picks, downloads, verifies and
caches the right one.

## ADDED Requirements

### Requirement: Lib releases
Pushing a tag `lib-v<version>`, where `<version>` equals the version in the crate's
`Cargo.toml`, SHALL publish a GitHub Release with one archive
`libnanuq_ffi-<version>-<target>.tar.gz` per supported target, and a file of SHA-256
sums for all archives. The supported targets SHALL be `x86_64-unknown-linux-gnu`,
`x86_64-unknown-linux-gnu-legacy-cpu`, `aarch64-unknown-linux-gnu`,
`aarch64-apple-darwin`, `x86_64-pc-windows-gnu` and `x86_64-pc-windows-gnu-legacy-cpu`.

#### Scenario: Tag pushed
- **WHEN** a maintainer pushes `lib-v0.1.0` and `Cargo.toml` says `0.1.0`
- **THEN** a release `lib-v0.1.0` appears with six archives and a sums file
- **AND** a pull request is opened that commits those sums to the repository

#### Scenario: Released from the Actions tab
- **WHEN** a maintainer runs the release workflow by hand on `main` with "publish"
  ticked, and no `lib-v<version>` tag exists for the `Cargo.toml` version
- **THEN** the same release and pull request are made, and the tag is created on the
  commit that was built

#### Scenario: Tag does not match the crate
- **WHEN** the tag's version differs from `Cargo.toml`
- **THEN** the workflow fails without publishing anything

### Requirement: Archives are tested before release
Each archive SHALL be smoke-tested, by compiling and running a Nanuq test against it on
its platform, before the release is published.

#### Scenario: Broken archive
- **WHEN** the smoke test fails for one target
- **THEN** no release is published for that tag

### Requirement: Portable binaries
Linux libraries SHALL link against glibc 2.28 or older symbols, macOS libraries SHALL
target macOS 11 or later, and the modern x86_64 builds SHALL require at most the
x86-64-v3 instruction set. Legacy-cpu builds SHALL require only baseline x86-64.

#### Scenario: Older Linux distribution
- **WHEN** a program is linked with the Linux library on a system with glibc 2.28
- **THEN** it links and runs

### Requirement: Committed checksums decide what can be downloaded
The package SHALL contain the lib version it expects and the SHA-256 of every archive
for that version. A compile SHALL download only an archive listed there, and SHALL
never download when the lib version ends in `-dev`.

#### Scenario: Development version
- **WHEN** the crate version is `0.2.0-dev`
- **THEN** no download is attempted and the library is built from source

#### Scenario: Platform without a prebuilt library
- **WHEN** compiling for a target not listed in the sums (e.g. `riscv64gc-unknown-linux-gnu`)
- **THEN** no download is attempted and the library is built from source, with a hint
  saying why

### Requirement: Download, verify and cache
When a prebuilt library is needed, the compile SHALL look in a per-user cache
directory keyed by lib version and target, and otherwise download the archive, verify
its SHA-256 against the committed sum, and unpack it into the cache. Every source the
compile uses SHALL be reported with a compiler hint. A checksum mismatch SHALL stop the
compile with an error and SHALL NOT fall back to building from source.

#### Scenario: First compile
- **WHEN** a program importing `nanuq` is compiled on Linux x86_64 with an empty cache
  and no local build
- **THEN** the archive is downloaded once, verified, cached and linked, and no cargo
  build runs

#### Scenario: Second project
- **WHEN** another project on the same machine imports the same Nanuq version
- **THEN** the cached library is linked without a download

#### Scenario: Tampered archive
- **WHEN** the downloaded archive's SHA-256 differs from the committed sum
- **THEN** compilation fails with an error naming the archive, the expected sum and the
  actual sum

#### Scenario: Offline
- **WHEN** the download fails (no network) and the lib policy is `auto`
- **THEN** the library is built from source, with a hint saying the download failed

### Requirement: CPU variant selection
On x86_64 Linux, when the compile target is the host, the compile SHALL pick the
legacy-cpu library if the host CPU lacks any feature the modern build needs. With
`-d:nanuqLegacyCpu` the legacy-cpu library SHALL be picked on every x86_64 target.
Otherwise the modern build SHALL be used.

#### Scenario: Old Linux CPU
- **WHEN** compiling on an x86_64 Linux host without AVX2
- **THEN** the `legacy-cpu` archive is used

#### Scenario: Forced legacy
- **WHEN** compiling for Windows x86_64 with `-d:nanuqLegacyCpu`
- **THEN** the `x86_64-pc-windows-gnu-legacy-cpu` archive is used
