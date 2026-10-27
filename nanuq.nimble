# Package

version       = "0.1.0"
author        = "Pietro Peterlongo"
description   = "Polars DataFrames for Nim, by wrapping the Rust library through a C ABI"
license       = "MIT"
srcDir        = "src"

# Dependencies

requires "nim >= 2.0.0"

# Tasks

task buildRust, "Build the Rust wrapper library (rust/target/release/libnanuq_ffi.a)":
  exec "cargo build --release --manifest-path rust/Cargo.toml"

task test, "Build the Rust wrapper and run the tests":
  exec "cargo build --release --manifest-path rust/Cargo.toml"
  exec "nim r --hints:off tests/test_basic.nim"

task example, "Run the basic example":
  exec "cargo build --release --manifest-path rust/Cargo.toml"
  exec "nim r --hints:off examples/basic.nim"

task docs, "Render the nimib dev log posts in docs/blog (needs nimib and ggplotnim)":
  exec "cargo build --release --manifest-path rust/Cargo.toml"
  for f in listFiles("docs/blog"):
    if f.endsWith(".nim"):
      exec "nim r --hints:off " & f

task specview, "Render the OpenSpec review page to specview.html, with file diffs against origin/main":
  exec "nim r --hints:off tools/specview.nim --base:origin/main"
