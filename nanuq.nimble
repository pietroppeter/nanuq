# Package

version       = "0.6.1"
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

task test, "Run every test file in one program (tests/all.nim); test_datamancer, test_arraymancer and test_database run only when Datamancer and db_connector are installed. One file: nim r tests/test_csv.nim":
  exec "nim r --hints:off tests/all.nim"

task example, "Run the basic example":
  exec "nim r --hints:off examples/basic.nim"

task docs, "Render the whole site in one program (docs/all.nim): the dev log posts, the index, the coverage map and the OpenSpec page (needs nimib, ggplotnim and Datamancer). One post: nim r docs/blog/move_37.nim":
  exec "nim r --hints:off docs/all.nim"

task specexamples, "Compile and run the Nim examples in openspec/specs and check their output":
  exec "nim r --hints:off tools/specexamples.nim"

task specview, "Render the OpenSpec review page to specview.html, with file diffs against origin/main":
  exec "nim r --hints:off tools/specview.nim --base:origin/main"
