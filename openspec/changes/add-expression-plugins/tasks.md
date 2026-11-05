## 1. Bridge

- [x] 1.1 `nq_expr_plugin` in src/rust/src/lib.rs; Polars features `ffi_plugin` and `dtype-extension`
- [x] 1.2 `nq_expr_plugin` in src/nanuq/ffi.nim

## 2. API

- [x] 2.1 `registerPluginFunction` in src/nanuq.nim
- [x] 2.2 tests/test_plugins.nim with the double_it fixture plugin
- [x] 2.3 Spec delta for `expression-plugins`, with an example
- [ ] 2.4 Before archiving: the spec suite builds tests/data/plugins/double_it.nim so the example runs
- [ ] 2.5 README and coverage map (`register_plugin_function`)
