## ADDED Requirements

### Requirement: Calling an expression plugin
`registerPluginFunction(pluginPath, functionName, args)` SHALL give an expression that
calls the function `functionName` of the Polars expression plugin at `pluginPath` (a
shared library implementing the Polars plugin ABI 0.1) on the columns of `args`, with
the options of Python's `register_plugin_function` (`kwargs` as pickled bytes,
`isElementwise`, `changesLength`, `returnsScalar`, `castToSupertype`,
`inputWildcardExpansion`, `passNameToApply`, `isDeterministic`). The output name and
data type SHALL be the ones the plugin reports, extension types included. The
expression SHALL compose like any other, lazily and in group-bys.

```nim
# tests/data/plugins/double_it.nim, built as a library
let lib = "tests/data/plugins/" & (DynlibFormat % "double_it")
let df = newDataFrame(series("x", [1.5, 2.0, 4.0]))
echo df.select(registerPluginFunction(lib, "double_it", [col"x"], isElementwise = true))
```

```text
shape: (3, 1)
┌─────┐
│ x   │
│ --- │
│ f64 │
╞═════╡
│ 3.0 │
│ 4.0 │
│ 8.0 │
└─────┘
```

#### Scenario: Plugin error
- **WHEN** the plugin reports an error for a call (it returns no column and sets its last error message)
- **THEN** running the query raises `ComputeError` with the plugin's message

#### Scenario: Missing library
- **WHEN** `pluginPath` is not a loadable library
- **THEN** running the query raises `ComputeError` naming the path

#### Scenario: Extension type output
- **WHEN** the plugin's output field carries `ARROW:extension:name`
- **THEN** the column has that extension type, shown as `ext[<name>]`
