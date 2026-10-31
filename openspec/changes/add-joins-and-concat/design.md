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
- Joins and concat read naturally from Nim: `a.join(b, on = ["k"], how = left)`.

**Non-Goals:**
- As-of and inequality joins (later releases, need more features and sorted keys).
- Changing Polars' defaults, such as making join order deterministic by default.

## Decisions

### One join function with all options
```rust
nq_lf_join(left, right, left_on: *const *const Expr, n_left, right_on: *const *const Expr,
           n_right, how: NqJoinType, suffix: *const c_char, validate: NqJoinValidation,
           nulls_equal: bool, coalesce: i32 /* -1 default, 0 keep, 1 coalesce */,
           maintain_order: NqJoinOrder) -> *mut LazyFrame
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
proc join*(lf, other: LazyFrame, on: openArray[string], how = inner, suffix = "_right",
           validate = manyToMany, nullsEqual = false, coalesce = none(bool),
           maintainOrder = noOrder): LazyFrame
proc join*(lf, other: LazyFrame, leftOn, rightOn: openArray[string], how = inner, ...)
proc join*(lf, other: LazyFrame, on: openArray[Expr], ...)            # and leftOn/rightOn
proc join*(lf, other: LazyFrame, how: JoinType, suffix = "_right", ...)  # cross join
```
plus the same on DataFrame. `on` / `leftOn` / `rightOn` are named, so
`a.join(b, on = ["k"])` and `a.join(b, leftOn = ["id"], rightOn = ["sid"])` both read
clearly. The keyless overload is meant for `how = cross` and raises `NanuqError` for
any other join type.

### Enum values named as in Polars
```nim
type
  JoinType* = enum inner, left, right, full, semi, anti, cross
  JoinValidation* = enum manyToMany, manyToOne, oneToMany, oneToOne
  JoinOrder* = enum noOrder, leftOrder, rightOrder, leftRightOrder, rightLeftOrder
  ConcatMethod* = enum vertical, verticalRelaxed, horizontal, diagonal, diagonalRelaxed
```
Nim 2 resolves overloaded enum values from the expected type, so `how = left` works
even if another symbol named `left` exists in another module (tested with Nim 2.2.4).
- *Why:* closest to Python's `how="left"` and to Rust's `JoinType::Left`.
- *Alternative:* prefixed values (`jtLeft`), the usual Nim style for exported enums.
  Safer against clashes, but further from Polars; the prefixed form stays available as
  `JoinType.left`.
- `JoinOrder` values carry an `Order` suffix so they never share a name with
  `JoinType` values.

### Concat
`nq_lf_concat(lfs: *const *const LazyFrame, n, how: NqConcat) -> *mut LazyFrame`:
`vertical` and `verticalRelaxed` call `concat` with `to_supertypes` false or true;
`diagonal` and `diagonalRelaxed` call `concat_lf_diagonal` with the same flag;
`horizontal` calls `concat_lf_horizontal`. In Nim, `concat(frames: openArray[LazyFrame],
how = vertical)` and the DataFrame version (lazy, concat, collect). An empty list
raises `NanuqError`, as in Polars.

## Risks / Trade-offs

- **Bare enum names in the `nanuq` namespace.** `left`, `right`, `inner`, `cross`,
  `vertical` and friends are exported. Overloaded enum resolution handles most
  clashes; the qualified form is the escape hatch.
- **Unordered joins by default.** Following Polars, a join's row order is not
  guaranteed unless `maintainOrder` is set. Tests and docs sort or set it. The README
  mentions it.
- **Binary size.** Three more Polars features; small next to the current library.
