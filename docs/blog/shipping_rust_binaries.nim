import nimib
import std/os
import ../nanuqtheme

nbInit
nb.title = "Shipping Nanuq's Rust binaries"
# dated slug for the dev log (module names can't start with a digit)
nb.doc.filename = nb.doc.filename.parentDir / "2026-10-27-shipping-rust-binaries.html"
nb.useNanuqTheme(
  titleHtml = "Shipping the <em>Rust</em> half",
  eyebrow = "Nanuq dev log · 27 October 2026",
  epigraph = "How do Nim users get libnanuq_ffi without a 10 minute Polars build, when there is no PyPI to upload wheels to?",
  meta = "Research · no code yet · rendered with nimib",
  summary = "How other Polars bindings ship their Rust half, and the plan for Nanuq's prebuilt libraries.",
)

nbText: """
The first build of Nanuq compiles Polars from source, which takes about ten minutes.
That's fine for us but not for someone trying the library for the first time. Python
users never see this because PyPI hosts a prebuilt wheel per platform. Nim has no such
registry, so this post looks at how other projects ship a native library without one,
and what Nanuq will do. Nothing here is implemented yet. It follows
[How Nanuq works](2026-10-27-how-nanuq-works.html).

> **The plan in one paragraph.** Do what Elixir's
> [Explorer](https://github.com/elixir-explorer/explorer) (Polars for Elixir) and
> [r-polars](https://github.com/pola-rs/r-polars) do. A GitHub Actions workflow, run
> when we push a `lib-v*` tag, builds the **static** library for four Rust targets and
> attaches the archives to a GitHub Release. The repository commits their **SHA-256
> sums**. At **compile time**, `ffi.nim` picks the archive for the host, downloads it
> once into a user cache with `curl`, checks the sum and links it. If anything is
> missing, it falls back to the cargo build we have today. It happens at compile time
> rather than in a nimble hook, because Atlas, nimby and plain git clones never run
> nimble hooks.

## Where Nanuq is today

`src/nanuq/ffi.nim` already does half of this. At compile time it looks for
`rust/target/release/libnanuq_ffi.a`, runs `cargo build` through `gorgeEx` if it's
missing, and accepts `-d:nanuqLibDir=…` for a library built elsewhere, or
`-d:nanuqNoCargo` to never run cargo. So the missing piece is a third source between
"already there" and "build it": "download a prebuilt one".

Three facts shape the choice:

- The crate builds both a `staticlib` and a `cdylib`. The static lib is about 300 MB
  unstripped.
- Nim on Windows uses MinGW gcc by default. A Rust static lib for the
  `x86_64-pc-windows-msvc` target won't link with MinGW, so the Windows build must be
  `x86_64-pc-windows-gnu`. r-polars ships `gnu` on Windows for the same reason (R uses
  Rtools gcc).
- Nim has no binary registry. Nimble, Atlas and nimby all install packages as git
  checkouts.

## How Nim packages ship native code

| Approach | Real examples | How it works | For Nanuq |
|---|---|---|---|
| Vendor C sources | status-im `sqlite3_abi`, naylib (raylib), nim-bearssl | C sources in the repo, compiled by Nim with `{.compile.}` | No: Rust needs cargo, and Polars takes minutes |
| Build at compile time | [nim-leopard](https://github.com/status-im/nim-leopard) (CMake through `gorge`), Nanuq today | The wrapper module runs a build tool when imported | Keep, as the fallback |
| Nimble `before install` hook | [nim-rocksdb](https://github.com/status-im/nim-rocksdb), the Nim compiler's own `nim.nimble` | Nimble runs NimScript before installing the package | Partial: Atlas, nimby, submodules and `nimble develop` skip it |
| Download prebuilt, else build | [nwaku's `build_rln.sh`](https://github.com/waku-org/nwaku/blob/master/scripts/build_rln.sh) | Fetch zerokit's Rust `librln.a` from GitHub Releases by host triple, else `cargo build` | Yes: the closest Nim precedent, and it's Rust |
| Fetch from a C package manager | [nimterop](https://github.com/nimterop/nimterop) `getHeader` with `-d:headerConan` / `-d:headerJBB` | Compile-time download from Conan Center or Julia BinaryBuilder | Shows the pattern is accepted, but nimterop is unmaintained |
| System library | sdl2, openssl, most wrappers | The user installs it with apt or brew | No: nobody packages a Polars C ABI |

Nimble itself downloads prebuilt Nim compilers now, but it has no mechanism for a
package's own native files. So whatever we do lives in the package.

## How other ecosystems do it

The useful models are the ecosystems that, like Nim, have no registry that knows about
platforms.

| Ecosystem | Mechanism | Takeaway |
|---|---|---|
| Elixir | [rustler_precompiled](https://hexdocs.pm/rustler_precompiled/precompilation_guide.html): at compile time, download the library for the host triple from GitHub Releases. A checksum file in the package pins every archive. `EXPLORER_BUILD=1` forces a cargo build, and a pre-release version always builds. Explorer ships 9 targets plus a `legacy_cpu` variant. | The best template: same library, same constraint |
| R | r-polars' [`tools/prep-lib.R`](https://github.com/pola-rs/r-polars/blob/main/tools/prep-lib.R) downloads from a separate `lib-v*` tag, checks `tools/lib-sums.tsv`, else builds with cargo | Version the Rust lib apart from the package |
| Go | Modules are source only and cgo has no build hooks. [wasmtime-go](https://github.com/bytecodealliance/wasmtime-go) commits prebuilt static libs into the repo on release tags | Fine for 20 MB, not for 300 MB times four targets |
| Deno | `Deno.dlopen` plus [@denosaurs/plug](https://jsr.io/@denosaurs/plug), which downloads a shared library on first use and caches it | Runtime download only suits dynamic libs |
| Zig | `build.zig.zon` dependencies are URLs pinned by content hash, fetched lazily into a global cache | Pin by hash, cache globally |
| Julia | [BinaryBuilder](https://docs.binarybuilder.org/stable/) cross-compiles everything. JLL packages carry an `Artifacts.toml` from platform to URL and hash | Our sums file is a small `Artifacts.toml` |

Ecosystems with a platform-aware registry still have ideas worth taking:

- **Python** ships platform wheels. Polars also publishes a build for old x86 CPUs
  (`polars-lts-cpu`, now `polars[rtcompat]`), so the CPU baseline needs a decision.
- **Node** started with install scripts (prebuild-install, node-pre-gyp) that download
  from GitHub Releases and fall back to node-gyp. It moved to one npm package per
  platform (napi-rs, esbuild, nodejs-polars) because install scripts broke behind
  corporate proxies. So errors must be clear, and a local path must always work.
- **Ruby** ships platform gems built with rb-sys plus a source gem that runs cargo.
  polars-ruby is shipped this way.

## The plan for Nanuq

### Compile-time download in ffi.nim

Before the cargo step, `ffi.nim` tries these sources in order:

1. `-d:nanuqLibDir=…` if given (exists today).
2. The local cargo output in `src/rust/target/release`, so contributors are unaffected.
3. The user cache: `~/.cache/nanuq/<libver>/<triple>/` (`%LOCALAPPDATA%` on Windows,
   `~/Library/Caches` on macOS). It is shared across projects and survives reinstalls.
4. A download of `libnanuq_ffi-<libver>-<triple>.tar.gz` with `curl` and `tar`, which
   ship with Windows 10 and later, macOS and mainstream Linux. The SHA-256 is checked
   with `sha256sum`, `shasum -a 256` or `certutil`, as r-polars does, since hashing
   100 MB in the Nim VM would be too slow.
5. A cargo build, as today.

Downloading is the default. `-d:nanuqLib=source` never downloads, and
`-d:nanuqLib=prebuilt` fails instead of building. Each step prints a hint, so a
compile that goes to the network says so.

### Platforms

| Target | Notes |
|---|---|
| `x86_64-unknown-linux-gnu` | Built against glibc 2.28 (manylinux container or `cargo zigbuild`), so it runs on older distros |
| `aarch64-unknown-linux-gnu` | On GitHub's arm runners, same glibc floor |
| `aarch64-apple-darwin` | With `MACOSX_DEPLOYMENT_TARGET=11.0` |
| `x86_64-pc-windows-gnu` | MinGW, to link with Nim's default C compiler. MSVC if someone asks |

Any other platform builds from source.

### CPU variants

Intel and AMD CPUs share a baseline instruction set, and newer ones add vector
instructions (AVX2, FMA) that process several numbers at once. Polars uses them in its
fast paths, but a library built to need them crashes on CPUs that lack them. We do what
Explorer does: each x86_64 target ships a modern build (x86-64-v3, roughly 2013 and
later) and a `legacy-cpu` baseline build. On Linux, `ffi.nim` reads `/proc/cpuinfo`
at compile time and picks the legacy build if a needed flag is missing. Elsewhere the
legacy build is only used with `-d:nanuqLegacyCpu`, which also forces it on Linux, for
example when the program will run on older machines than the one compiling it. arm64
has a single build.

### Static, not dynamic

The static lib makes the user's program self-contained: nothing to find at runtime and
no DLL search paths. That's also what nwaku and r-polars ship. The costs are a big
download and slower links. A shared library option stays in the backlog. The release
can carry both kinds later, since the crate already builds both.

Size needs measuring first: `lto = "fat"` and `codegen-units = 1` should shrink the
archive, and gzip keeps it readable by every `tar`.

### Versions

- The lib is versioned by the crate's `Cargo.toml`, apart from the Nim package, and its
  binaries live under a `lib-v<libver>` tag. Most Nim releases reuse the last lib.
  Lib releases are tagged by hand.
- The sums are committed in `src/nanuq/lib-sums.txt` and read with `staticRead`.
- A `-dev` lib version never downloads. CI fails if the crate changed while the version
  still matches a published lib, so new Rust code is never paired with an old binary.
- Rust exports `nq_version()`, and Nanuq checks it at startup.

### Fallback

Every miss falls back to cargo with a hint saying why, for example
*"nanuq: no prebuilt library for riscv64gc-unknown-linux-gnu, building with cargo
(about 10 minutes)"*. A checksum mismatch is the exception: it stops with an error,
because it may mean a release was replaced. Without cargo, the error names both ways
out: install Rust, or download the archive by hand and pass `-d:nanuqLibDir`.

### The release workflow

```yaml
on: push: tags: ["lib-v*"]
jobs:
  build:    # matrix over the targets above, plus legacy-cpu for x86_64
    - cargo build --release --target $TRIPLE   (zigbuild for linux-gnu.2.28)
    - tar czf libnanuq_ffi-$VER-$TRIPLE.tar.gz libnanuq_ffi.a
    - smoke test: nim c -r -d:nanuqLibDir=. tests/test_basic.nim
  release:
    - sha256sum *.tar.gz > lib-sums.txt
    - create the GitHub Release with the archives and lib-sums.txt
    - open a PR that commits src/nanuq/lib-sums.txt
```

## Set aside

- **Binaries in git** (wasmtime-go's way) or Git LFS: 300 MB per target would bloat
  every clone, and Nimble doesn't handle LFS.
- **One nimble package per platform**, like npm's per-platform packages: the binaries
  still need a git home, and the package managers resolve requirements differently.
- **A nimble hook only**: misses Atlas, nimby, submodules and `nimble develop`.
- **Runtime download**: only works for dynamic libs, and a data library that goes
  online on first run would surprise people.

One more thing turned up while writing the OpenSpec change: `nimble install` copies only
`srcDir`, so a top-level `rust/` never reaches users. The crate therefore moves to
`src/rust/`, which also keeps the cargo fallback working in installed packages.
"""

nbSave
