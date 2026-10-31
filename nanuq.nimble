# Package

version       = "0.1.0"
author        = "Pietro Peterlongo"
description   = "Polars DataFrames for Nim, by wrapping the Rust library through a C ABI"
license       = "MIT"
srcDir        = "src"
skipDirs      = @["target"]  # local cargo output in src/rust/target (nimble matches dir names)

# Dependencies

requires "nim >= 2.0.0"

# Tasks

# test, example and docs link the prebuilt library (see src/nanuq/ffi.nim), or the
# local build in src/rust/target/release once `nimble buildRust` has made one.

task buildRust, "Build the Rust wrapper library (src/rust/target/release/libnanuq_ffi.a)":
  exec "cargo build --release --manifest-path src/rust/Cargo.toml"

task test, "Run the tests (tests/test_datamancer.nim needs Datamancer installed)":
  for t in ["tests/test_basic.nim", "tests/test_nulls.nim", "tests/test_datatypes.nim",
            "tests/test_combining.nim", "tests/test_verbs.nim",
            "tests/test_datasets.nim", "tests/test_html.nim",
            "tests/test_datamancer.nim"]:
    exec "nim r --hints:off " & t

task example, "Run the basic example":
  exec "nim r --hints:off examples/basic.nim"

task docs, "Render the nimib dev log posts in docs/blog, then the index (needs nimib, ggplotnim and Datamancer)":
  for f in listFiles("docs/blog"):
    if f.endsWith(".nim"):
      exec "nim r --hints:off " & f
  exec "nim r --hints:off docs/index.nim"

task specview, "Render the OpenSpec review page to specview.html, with file diffs against origin/main":
  exec "nim r --hints:off tools/specview.nim --base:origin/main"
