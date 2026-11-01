# Package

version       = "0.4.0"
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

task test, "Run the tests (test_datamancer and test_arraymancer need Datamancer, which brings Arraymancer)":
  for t in ["tests/test_basic.nim", "tests/test_nulls.nim", "tests/test_datatypes.nim",
            "tests/test_combining.nim", "tests/test_verbs.nim", "tests/test_expressions.nim",
            "tests/test_selectors.nim", "tests/test_csv.nim",
            "tests/test_datasets.nim", "tests/test_html.nim", "tests/test_inspection.nim", "tests/test_strings.nim", "tests/test_temporal.nim", "tests/test_io.nim", "tests/test_categorical.nim", "tests/test_math.nim", "tests/test_cumulative.nim", "tests/test_rolling.nim", "tests/test_values.nim", "tests/test_horizontal.nim", "tests/test_reshaping.nim", "tests/test_timegroups.nim", "tests/test_series.nim", "tests/test_rows.nim", "tests/test_nested.nim", "tests/test_lists.nim", "tests/test_structs.nim", "tests/test_json.nim", "tests/test_sql.nim", "tests/test_callbacks.nim", "tests/test_utilities.nim",
            "tests/test_datamancer.nim", "tests/test_arraymancer.nim"]:
    exec "nim r --hints:off " & t

task example, "Run the basic example":
  exec "nim r --hints:off examples/basic.nim"

task docs, "Render the nimib dev log posts in docs/blog, then the index (needs nimib, ggplotnim and Datamancer)":
  for f in listFiles("docs/blog"):
    if f.endsWith(".nim"):
      exec "nim r --hints:off " & f
  exec "nim r --hints:off docs/index.nim"

task specexamples, "Compile and run the Nim examples in openspec/specs and check their output":
  exec "nim r --hints:off tools/specexamples.nim"

task specview, "Render the OpenSpec review page to specview.html, with file diffs against origin/main":
  exec "nim r --hints:off tools/specview.nim --base:origin/main"
