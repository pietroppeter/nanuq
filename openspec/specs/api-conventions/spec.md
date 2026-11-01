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

### Requirement: Python's `method` parameter is `how`
`method` is a Nim keyword, so no parameter can have that name. Where Python Polars has a
`method` parameter that picks a variant from a closed set, Nanuq SHALL call it `how`, the
name Polars itself uses for `join` and `concat`. This applies to `rank`, `corr` and
`interpolate`. Where Python uses another name (`quantile`'s `interpolation`), Nanuq SHALL
keep Python's name.

```nim
let df = newDataFrame:
  x: [1.0, 2.0, 2.0, 4.0]
  y: [1.0, 4.0, 4.0, 16.0]
echo df.select(col.x.rank(how = Dense).alias("dense"),
               col.x.rank(Min).alias("min"))
echo df.select(corr("x", "y", how = Spearman).alias("spearman"))
```

```text
shape: (4, 2)
┌───────┬─────┐
│ dense ┆ min │
│ ---   ┆ --- │
│ u32   ┆ u32 │
╞═══════╪═════╡
│ 1     ┆ 1   │
│ 2     ┆ 2   │
│ 2     ┆ 2   │
│ 3     ┆ 4   │
└───────┴─────┘
shape: (1, 1)
┌──────────┐
│ spearman │
│ ---      │
│ f64      │
╞══════════╡
│ 1.0      │
└──────────┘
```

#### Scenario: Named variant
- **WHEN** user code writes `corr("x", "y", how = Spearman)` or `rank(how = Dense)`
- **THEN** it compiles and picks that variant

#### Scenario: Positional variant
- **WHEN** user code writes `rank(Min)` or `corr("x", "y", Spearman)`
- **THEN** it means the same as naming `how`

### Requirement: Parameters that take several types use converter types
Where Python Polars lets a parameter take values of different types (a name or a list of
names, a duration string or a number) and the parameter needs a default, Nanuq SHALL use
a small exported object type with a `converter` from each accepted type, instead of a
generic union (`string | openArray[string] = []` does not compile with a default in Nim)
or one overload per combination. The existing types are `ColumnNames` (a name, a seq or an
array of names), `OptInterval` (a std/times interval or a duration string), `JoinKey` (a
column name or an expression) and `AsofTolerance` (an interval, a duration string, an int
or a float). A new parameter of this kind SHALL reuse one of them when it fits, and a new
type SHALL be listed here. Converters SHALL only convert into these types, so they apply
only where such a parameter appears.

```nim
let df = newDataFrame:
  year: [1997, 1997, 1998]
  months: ["JJA", "SON", "JJA"]
  anomaly: [1.5, 2.3, -0.2]
echo df.pivot("months", index = "year", values = "anomaly").columns
echo df.pivot(["months"], index = @["year"], values = "anomaly").columns
```

```text
@["year", "JJA", "SON"]
@["year", "JJA", "SON"]
```

#### Scenario: One name or a list
- **WHEN** user code passes `index = "year"` or `index = ["year", "month"]` to `pivot`
- **THEN** both compile and mean one or two index columns

#### Scenario: Default left out
- **WHEN** user code calls `joinAsof(other, on = "t")` without `tolerance`
- **THEN** it compiles, and no tolerance is applied
