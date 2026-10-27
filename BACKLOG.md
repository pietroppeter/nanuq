# Backlog

Ideas and possible next steps for Nanuq. An idea that gets picked up becomes an
OpenSpec change (`openspec/changes/`, `/opsx:propose`). Add it to the change's
proposal, then remove it from here, or tick it and link the change.

Each entry says what the idea is and why it matters. Rough size: S (hours), M (a day or
two), L (more).

## Distribution

- [ ] **Prebuilt binaries for users** (M). A release workflow builds `libnanuq_ffi` for
  Linux x64, macOS arm64 and Windows and attaches it to GitHub Releases. `ffi.nim`
  downloads the one matching the package version at compile time and falls back to
  cargo. This removes the ~10 minute first build for users.
- [ ] **`nimble install` support** (S-M). Today the package expects `rust/` next to `src/`.
  Pairs with prebuilt binaries.
- [ ] **Shared library option** (M). Ship `.so` / `.dylib` / `.dll` instead of the static
  lib (about 300 MB unstripped), with runtime loading.

## Bridge

- [ ] **Generate `ffi.nim` with nbindgen** (S-M). Generate the Nim declarations from the
  Rust code instead of writing them by hand, and add a CI check that the generated file
  is up to date. Pietro said yes, but not yet (2026-10-27).
- [ ] **Zero-copy columns through the Arrow C Data Interface** (L). Move whole columns
  between Nim and Polars without copying.

## API

- [ ] **More IO** (M): Parquet, JSON, lazy `scanCsv` / `scanParquet`.
- [ ] **Joins** (M): inner, left, outer, cross.
- [ ] **Nulls and more dtypes** (M): null handling (`Option`), dates and datetimes,
  categoricals.
- [ ] **More expressions** (M): `when/then/otherwise`, string functions, casting, window
  functions (`over`).
- [ ] **Column access as Nim seqs without per-cell calls** (S). Bulk copy instead of
  `toSeq` reading cell by cell.

## Docs

- [ ] **Blog index page** (S). A list of dev-log posts instead of redirecting to the
  latest one.
- [ ] **Official documentation** (L). A reference and guides, separate from the dev log.
