# Proposal

## Why

Nanuq 0.2 runs the PDS-H benchmark (scale factor 1) about 4x slower than py-polars on
the same machine: 13.6 s against 3.07 s on an M3 Pro. The performance investigation
(BACKLOG.md, Performance) traced almost all of it to how the library is built, not to
the wrapper: py-polars is compiled with nightly Rust and Polars' `nightly` feature
(SIMD and other nightly-only code paths) and uses jemalloc. Measured on the same Mac,
best of 3:

| Build | PDS-H SF1 |
|---|---|
| py-polars 2.1 | 3.07 s |
| prebuilt lib-v0.2.0 (stable) | 13.6 s |
| nightly + `polars/nightly` | 3.56 s |
| nightly + `polars/nightly` + jemalloc | 3.20 s (1.04x py-polars) |

Polars' git version, the `performant` feature, CSE and the streaming engine made no real
difference. This change was requested by Pietro on 2026-10-31 for 0.3.

## What Changes

- **Crate features**, both off by default so that local builds keep working on stable
  Rust: `nightly = ["polars/nightly"]` and `jemalloc = ["dep:tikv-jemallocator"]`
  (tikv-jemallocator 0.6, optional), which sets jemalloc as Rust's global allocator.
- **Release archives** (release-lib.yml) are built with a pinned toolchain,
  `nightly-2026-04-01`, and `--features "nightly jemalloc"`; Windows uses `nightly`
  only (py-polars uses mimalloc there, and jemalloc does not build for windows-gnu).
  aarch64 Linux builds set `JEMALLOC_SYS_WITH_LG_PAGE=16`, as Polars does, so they also
  run on kernels with 64 KiB pages. No `rust-toolchain.toml`: stable stays the default.
- **`str.toTitlecase`**, which Polars only has with its nightly feature: available with
  the release libraries; a stable local build raises `InvalidOperationError`.
- The release smoke test also runs `tests/test_strings.nim` with `-d:nanuqNightly`, which
  checks that the archive was built with the nightly feature.
- Polars stays at 0.55.2.

## Capabilities

### Modified Capabilities
- `binary-distribution`: how release archives are built.
- `strings`: `str.toTitlecase`.

## Differences from Polars

- None in behaviour: this matches how py-polars is built. `toTitlecase` depends on the
  library build, which Python users never see.

## Impact

- `src/rust/Cargo.toml` (features, optional dependency), `src/rust/src/lib.rs` (global
  allocator, `ToTitlecase`), `src/nanuq/ffi.nim`, `src/nanuq.nim`.
- `.github/workflows/release-lib.yml`; `openspec/config.yaml` context ("stable Rust").
- jemalloc as Rust's global allocator is safe because every Rust allocation is freed by
  Rust through the `nq_*_free` functions; Nim never frees Rust memory itself.
