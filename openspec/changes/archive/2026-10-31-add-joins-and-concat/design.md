# Design

## Context

Lazy verbs cross the ABI as functions that borrow a `LazyFrame` and return a new one
(`nq_lf_filter`, `nq_lf_cast`, ...). Lists of expressions are passed as a pointer and
a length, and enums as `#[repr(C)]` integers mirrored in `ffi.nim`. DataFrame verbs are
eager shortcuts: `df.lazy.<verb>.collect`. In Polars 0.55, `LazyFrame::join(other,
left_on, right_on, JoinArgs)` takes `JoinArgs { how, validation, suffix, nulls_equal,
coalesce, maintain_order, .. }`, and concatenation is `concat(lfs, UnionArgs)`,
`concat_lf_diagonal` and `concat_lf_horizontal`.

## Goals / Non-Goals

**Goals:**
- Every equi-join type and option Python Polars exposes, with the same defaults.
- One Rust function per verb, so options are added without new ABI functions.
- Joins and concat read naturally from Nim: `a.join(b, on = ["k"], how = Left)`.
- One rule for option values that every later change reuses.

**Non-Goals:**
- As-of and inequality joins (later releases, need more features and sorted keys).
- Changing Polars' defaults, such as making join order deterministic by default.

## Decisions

### One join function with all options
```rust
nq_lf_join(left, right, left_on: *const *const Expr, n_left, right_on: *const *const Expr,
           n_right, how: NqJoinType, suffix: *const c_char, validate: NqJoinValidation,
           nulls_equal: bool, coalesce: i32 /* -1 default, 0 keep, 1 coalesce */,
           maintain_order: NqMaintainOrderJoin) -> *mut LazyFrame
```
Nim builds the key expressions (`col(name)` for strings) and passes both lists; for
`on` the same list goes on both sides. A cross join passes empty lists, and Rust
rejects keys on a cross join and a missing key on any other join with a clear error.
- *Why:* a single entry point keeps the ABI small; the options map one to one onto
  `JoinArgs`.
- *Alternative:* an options struct across the ABI. More layout to keep in sync for no
  gain at this size.

### Nim procs
```nim
proc join*(lf, other: LazyFrame, on: openArray[string], how = JoinType.Inner,
           suffix = "_right", validate = JoinValidation.ManyToMany, nullsEqual = false,
           coalesce = none(bool), maintainOrder = MaintainOrderJoin.None): LazyFrame
proc join*(lf, other: LazyFrame, leftOn, rightOn: openArray[string], how = JoinType.Inner, ...)
proc join*(lf, other: LazyFrame, on: openArray[Expr], ...)            # and leftOn/rightOn
proc join*(lf, other: LazyFrame, how: JoinType, suffix = "_right", ...)  # cross join
```
plus the same on DataFrame. `on` / `leftOn` / `rightOn` are named, so
`a.join(b, on = ["k"])` and `a.join(b, leftOn = ["id"], rightOn = ["sid"])` both read
clearly. The keyless overload is meant for `how = Cross` and raises `NanuqError` for
any other join type.

### Option values: pure enums with Rust's names (Nanuq-wide)
```nim
type
  JoinType* {.pure.} = enum Inner, Left, Right, Full, Semi, Anti, Cross
  JoinValidation* {.pure.} = enum ManyToMany, ManyToOne, OneToMany, OneToOne
  MaintainOrderJoin* {.pure.} = enum None, Left, Right, LeftRight, RightLeft
  ConcatMethod* {.pure.} = enum Vertical, VerticalRelaxed, Horizontal, Diagonal, DiagonalRelaxed
```
The rule, for every option type now and later: use the Rust Polars enum's type name and
variant names, as a `{.pure.}` enum. Only when Rust has no enum (as for concat) does
Nanuq name one, following Python's strings in PascalCase.
- *Why:* NEP 1 allows unprefixed values only for pure enums, in PascalCase, and the
  stdlib does the same (`SortOrder.Ascending`). Rust's names need no invention, map one
  to one onto Polars' Rust docs, and may repeat across types (`JoinType.Left`,
  `MaintainOrderJoin.Left`) because a pure value is resolved from the expected type,
  or qualified. Checked with Nim 2.2.4: `join(how = Left, maintainOrder = Left)`
  compiles and picks each type's value; `let x = Left` is ambiguous and must be
  qualified.
- *Alternatives considered* (design note of 2026-10-31): strings like Python (runtime
  typos, no completion, unusual in Nim); short prefixes `jtLeft` (NEP 1's default,
  cryptic, far from Polars); long prefixes `joinLeft` (verbose, needs invented
  prefixes); bare camelCase `left` (against NEP 1, forced the `leftOrder` workaround);
  one proc per variant `leftJoin` (still needs enums for the other options; possible
  later as sugar).
- `DataTypeKind` follows the rule: `DataTypeKind.Int64`, `DataTypeKind.Other`. Pure
  enum values and the `DataType` constants of the same name coexist: a bare `Int64`
  where a `DataType` is expected picks the constant (checked).
- The enums in `ffi.nim` (`NqJoinType`, ...) are internal and keep their `nq` prefix.

### Concat
`nq_lf_concat(lfs: *const *const LazyFrame, n, how: NqConcat) -> *mut LazyFrame`:
`Vertical` and `VerticalRelaxed` call `concat` with `to_supertypes` false or true;
`Diagonal` and `DiagonalRelaxed` call `concat_lf_diagonal` with the same flag;
`Horizontal` calls `concat_lf_horizontal`. In Nim, `concat(frames: openArray[LazyFrame],
how = ConcatMethod.Vertical)` and the DataFrame version (lazy, concat, collect). An empty list
raises `NanuqError`, as in Polars.

## Risks / Trade-offs

- **Capitalised bare values in the namespace.** `Left`, `Inner`, `Vertical`, ... are
  exported. Overload resolution by expected type makes clashes harmless in typed
  contexts; the qualified form is the escape hatch.
- **Breaking `DataTypeKind`.** Only code that names kinds (`case t.kind`) changes; the
  constants users write stay the same. Nanuq has no outside users yet.
- **Unordered joins by default.** Following Polars, a join's row order is not
  guaranteed unless `maintainOrder` is set. Tests and docs sort or set it. The README
  mentions it.
- **Binary size.** Three more Polars features; small next to the current library.
