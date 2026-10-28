# Spec Delta

## MODIFIED Requirements

### Requirement: Linking the static library
Importing `nanuq` SHALL link `libnanuq_ffi.a` from the first of these sources that has
it: the directory given with `-d:nanuqLibDir`, the local cargo output of the crate in
`src/rust/`, the prebuilt library (see `binary-distribution`), and finally a cargo build
of `src/rust/` run at compile time. `-d:nanuqLib=auto` (the default) allows all
sources. `-d:nanuqLib=prebuilt` (or `-d:nanuqNoCargo`) never runs cargo.
`-d:nanuqLib=source` never downloads. The crate SHALL ship inside the installed
package, so the cargo fallback also works after `nimble install`.

#### Scenario: Library missing, cargo allowed
- **WHEN** no local library exists, no prebuilt library is available, and the policy is
  `auto` or `source`
- **THEN** compilation runs `cargo build --release` for `src/rust/` and links the result

#### Scenario: Library missing, cargo disabled
- **WHEN** no local or prebuilt library is available and the policy is `prebuilt`
- **THEN** compilation fails with an error naming the expected library path and how to
  get one

#### Scenario: Installed with nimble
- **WHEN** a user runs `nimble install nanuq` on a platform without a prebuilt library
  and has cargo
- **THEN** compiling a program that imports `nanuq` builds the library from the
  installed package's sources and links it

## ADDED Requirements

### Requirement: Library version check
The library SHALL report its version through the C ABI. At startup, Nanuq SHALL compare
it with the lib version it was compiled for and stop with an error naming both versions
if they differ.

#### Scenario: Stale library
- **WHEN** `-d:nanuqLibDir` points at a library built from an older crate version
- **THEN** the program stops at startup with an error naming both versions
