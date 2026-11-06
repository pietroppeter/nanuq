# Proposal

## Why

Polars can be extended with **expression plugins**: shared libraries that Polars loads
and calls on Arrow arrays (Python's `register_plugin_function`). They are how
polars-stats (vectorized distributions) and similar extensions ship. The plugin
boundary is a plain C ABI (polars-ffi `version_0`, ABI 0.1), so a plugin can be
written in Rust with pyo3-polars, or in Nim.

The exploration "Polars plugins, without the Rust" (nanuq-more, 2026-11-05) wrote two
plugins in Nim (ISO weeks as an extension type, and probability distributions) and
loaded the same library from Python Polars and from Nanuq. Nanuq needed one new
function for that, which this change proposes. Not from a BACKLOG.md entry.

## What Changes

- `registerPluginFunction(pluginPath, functionName, args, kwargs, isElementwise,
  changesLength, returnsScalar, castToSupertype, inputWildcardExpansion,
  passNameToApply, isDeterministic): Expr`, as in Python Polars. `kwargs` are bytes
  already pickled (a dict), as Polars passes them to the plugin.
- The C bridge gets `nq_expr_plugin`, which builds `FunctionExpr::FfiPlugin`. The crate
  enables the Polars features `ffi_plugin` (polars-plan and polars-lazy) and
  `dtype-extension`, so a plugin can return an extension type (`ext[...]`).
- `tests/test_plugins.nim` builds a minimal Nim plugin (`tests/data/plugins/double_it.nim`,
  the ABI by hand) and checks a call, an error and a lazy group-by.

## Capabilities

### New Capabilities
- `expression-plugins`: calling Polars expression plugins from Nanuq.

## Differences from Polars

- Python resolves a relative `plugin_path` against the virtual environment and also
  accepts a directory; Nanuq takes the library file, relative to the working directory
  (made absolute), and has no `use_abs_path`.
- Python pickles a `kwargs` dict itself; Nanuq takes the pickled bytes (nanuq-more has a
  small pickle writer). A typed kwargs parameter could come later.
- Rust Polars builds the same expression through `Expr::Function` with
  `FunctionExpr::FfiPlugin`; it has no public helper of this name.
- Extension types show as `ext[<name>]` (Python shows the registered class's repr);
  Nanuq has no registry of extension classes.

## Impact

- `src/rust/Cargo.toml` (features), `src/rust/src/lib.rs`, `src/nanuq/ffi.nim`,
  `src/nanuq.nim`, a new test and its fixture. Needs a new library release.
- Rust plugins built with pyo3 (polars-stats) link against libpython: Nanuq can load
  them only with libpython preloaded (`LD_PRELOAD`). Plugins written in Nim (or plain
  Rust without pyo3) load directly.
- The plugin ABI is Polars' version 0 and extension types are unstable in Polars:
  either may change in a Polars release.
