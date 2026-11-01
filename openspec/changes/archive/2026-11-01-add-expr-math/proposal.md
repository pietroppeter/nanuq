# Proposal

## Why

The Nanuq Book ports stopped on elementwise math more often than on anything else that
needs no new data type: the O'Reilly chapter 8 sections on mathematical transformations,
trigonometry, rounding and missing or infinite values, and every query that takes a
square root or a logarithm. NaN, which Polars keeps apart from null, has no API at all.

It is the first change of the 0.4 release ("A real Series, and shaping", see the
Polars coverage map).

## What Changes

- Elementwise math on expressions: `sqrt`, `cbrt`, `exp`, `log(base = E)`, `log10`,
  `log1p`, `sign`, `floor`, `ceil`, `clip(lowerBound, upperBound)` (or one bound, named),
  and `dot(other)`.
- Trigonometry: `sin`, `cos`, `tan`, `cot`, `arcsin`, `arccos`, `arctan`, `sinh`,
  `cosh`, `tanh`, `arcsinh`, `arccosh`, `arctanh`, `degrees`, `radians`, and
  `arctan2(y, x)`.
- NaN and infinity: `isNan`, `isNotNan`, `isFinite`, `isInfinite`, `fillNan(value)`,
  `dropNans`, and `Expr.dropNulls`.
- The wrapper crate becomes `0.4.0-dev` and gains the Polars features 0.4 needs.

## Capabilities

### New Capabilities
- `math-functions`: elementwise math, trigonometry, NaN and infinity.

## Differences from Polars

- `clip` with one bound needs the bound named (`clip(lowerBound = 0)`): a single
  positional argument is a compile error, because Nim can't tell which bound it is.
  Python takes `clip(lower_bound=None, upper_bound=None)`; Rust has `clip`,
  `clip_min` and `clip_max`.
- `log(base)` defaults to e as in Python (Rust always takes the base). Nim's std/math
  `ln`, `log2` are not added; `log(2.0)` does that.
- `arctan2(y, x)` is a free function as in Python (`pl.arctan2`); in Rust it is a method.
- These names overload std/math's float procs (`sqrt`, `exp`, `floor`, ...) for `Expr`;
  both work in the same module.

## Impact

- `src/rust/Cargo.toml` (version, features), `src/rust/src/lib.rs` (`NqUnary` grows,
  `nq_expr_clip`, `nq_expr_log`, `nq_expr_binary_fn`), `src/nanuq/ffi.nim`,
  `src/nanuq.nim`.
- New `tests/test_math.nim`.
