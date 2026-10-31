# api-conventions Specification

## Purpose
Naming conventions that every part of the Nanuq API follows: Polars names in camelCase,
and closed sets of option values as pure enums with Rust Polars names.

## Requirements

### Requirement: Option values are pure enums with Rust Polars names
A parameter that takes one of a closed set of option values SHALL use a `{.pure.}` enum
whose type name and PascalCase value names are those of the corresponding Rust Polars
enum (e.g. `JoinType.Left` for `JoinType::Left`). When Rust Polars has no such enum,
Nanuq SHALL name one after Python Polars' parameter strings, in PascalCase. Strings
SHALL NOT be used for closed sets of options. Internal C ABI enums in `ffi.nim` keep
their `Nq`/`nq` prefixes and are exempt.

```nim
let a = newDataFrame(series("k", [1, 2]))
let b = newDataFrame(series("k", [2, 3]))
echo a.join(b, on = ["k"], how = Left, maintainOrder = Left).shape   # JoinType.Left, MaintainOrderJoin.Left
let how = JoinType.Full    # outside a typed parameter, qualify the value
echo a.join(b, on = ["k"], how = how).shape
```

```text
(2, 1)
(3, 2)
```

#### Scenario: Bare value in a typed context
- **WHEN** user code passes `how = Left` to `join`
- **THEN** it compiles and means `JoinType.Left`

#### Scenario: Shared value names
- **WHEN** user code passes `how = Left, maintainOrder = Left`
- **THEN** each resolves to its own enum's value, as in Rust

#### Scenario: Untyped context
- **WHEN** user code writes `let x = Left` with several enums exporting `Left`
- **THEN** compilation fails as ambiguous, and `let x = JoinType.Left` compiles

### Requirement: The conventions are documented
The README SHALL state the API conventions (camelCase Polars names, pure enums with
Rust names for option values), and every OpenSpec proposal SHALL follow them, listing
any exception in its "Differences from Polars" section.

#### Scenario: New option type
- **WHEN** a proposal adds a parameter with a closed set of values
- **THEN** it uses the Rust Polars enum name and values as a pure enum, or explains why not
