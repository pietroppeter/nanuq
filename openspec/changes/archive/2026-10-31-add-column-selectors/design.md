# Design

## Context

In Polars 0.55, a `Selector` (`polars_plan::dsl::Selector`) is a tree: `ByName`,
`Matches(regex)`, `ByDType(DataTypeSelector)`, `Wildcard`, plus set operations.
`DataTypeSelector` has `AnyOf([DataType])`, `Integer`, `SignedInteger`,
`UnsignedInteger`, `Float` and `Numeric`, among others. `Selector::exclude_cols(names)`
removes names, and `Selector::as_expr()` turns a selector into an `Expr` that Polars
expands against the schema. `col("^...$")` is already a regex selector.
`Expr::name().suffix(s)` and `.prefix(s)` rename outputs.

## Goals / Non-Goals

**Goals:**
- Selectors in idiomatic Nim (types and typeclasses), with no extra namespace to import.
- No opaque selector handles across the ABI.

**Non-Goals:**
- Set operators, by-index selection, and name helpers beyond regex.

## Decisions

### `Selector` is a Nim value built into an `Expr` on use
A Nim `Selector` object holds what was asked for: `names: seq[string]`,
`dtypes: seq[DataType]`, `classes: set[DtypeClass]`, `wildcard: bool` and
`excluded: seq[string]`. `exclude` returns a copy with more excluded names. A
`converter toExpr(s: Selector): Expr` makes one call:

```rust
nq_expr_selector(names: *const *const c_char, n_names: usize, dtypes: *const NqDtype,
                 n_dtypes: usize, classes: u32 /* bit set of NqDtypeClass */,
                 wildcard: bool, excluded: *const *const c_char, n_excluded: usize)
                 -> *mut Expr
```
Rust takes the union of the parts (`ByName` | `ByDType(AnyOf)` | `ByDType(category)` |
`Wildcard`), applies `exclude_cols`, and returns `as_expr()`.
- *Why:* it is the same pattern as the conditional chain (built in Nim, crossed once).
  Selectors stay plain values, and `$` shows Polars' rendering of the selector.
- *Alternative:* an opaque `NqSelector` with its own free function. That means more ABI
  surface, and it gains nothing until set operators exist.

### Types and typeclasses
`col(T: typedesc)` is a macro. It looks at the type it is given:
- `SomeNumber`, `SomeInteger`, `SomeSignedInt`, `SomeUnsignedInt` and `SomeFloat` map to
  the matching `DtypeClass`.
- A concrete type maps through `dataType(T)`, so `col(int)` is `Int64` and `col(int8)`
  is `Int8`, the same rules as `cast`.
- `col(float, int)` takes several types and unions them.
- Any other type is a compile error with the message of `dataType`.

### Several names
`col(a, b: string, more: varargs[string])` returns a `Selector`, so `col("a")` keeps
returning `Expr` with no ambiguity. `all()` sets `wildcard`. Regex needs no new code,
because `col("^w.*$")` already passes the pattern to Polars.

### Output names
`proc name(e: Expr): ExprName` returns a small wrapper. `suffix(n: ExprName, s)` and
`prefix(n: ExprName, s)` call `nq_expr_name_affix(e, s, is_prefix)`. A `Selector` reaches
`name` through the converter.

## Risks / Trade-offs

- Converters make overload errors harder to read. They are limited to
  `Selector -> Expr`, the same as `Then -> Expr`.
- Typeclass dispatch in a macro depends on how Nim represents `SomeNumber` symbols. The
  tests cover each typeclass and a concrete type.
