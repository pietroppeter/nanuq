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

task docs, "Render the nimib walkthrough to docs/walkthrough.html (needs nimib)":
  exec "cargo build --release --manifest-path rust/Cargo.toml"
  exec "nim r --hints:off docs/walkthrough.nim"
