# Tasks

## 1. Bridge

- [ ] 1.1 Add the Polars feature `rank` and move the crate to `0.3.0-dev`
- [ ] 1.2 Map `NqBinOp::Div` to `true_div`; add `NqUnary::NullCount`
- [ ] 1.3 Add `nq_expr_rank` with `NqRankMethod`
- [ ] 1.4 Mirror everything in `ffi.nim`; verify that `cargo build --release` passes

## 2. Nim API

- [ ] 2.1 Rename `toSeq` to `toList` everywhere (library, Datamancer module, tests, README, dev log posts, examples)
- [ ] 2.2 Turn `col` into a `ColNs` constant with call operators for every existing form and a dot template
- [ ] 2.3 Turn `newDataFrame` into a macro with the block syntax (`nil` as missing, string keys) that forwards other calls to the series form
- [ ] 2.4 Add `Expr.nullCount` and `rank` with `RankMethod`
- [ ] 2.5 Tests: `toSeq(walkFiles(...))` compiles with Nanuq imported, `col.name` gives the same plan as `col("name")`, the block syntax (nil, string keys, compile failure for only nil), true division and division by zero, `nullCount` in `agg`, every `RankMethod`

## 3. Docs and integration

- [ ] 3.1 README: `toList`, `col.name`, the block syntax and true division; verify that `nimble test`, `nimble example` and `nimble specexamples` pass
- [ ] 3.2 Archive the change: remove the three BACKLOG entries, add CHANGELOG lines (Changed for `/` and `toList`), update spec example outputs with `--update`
