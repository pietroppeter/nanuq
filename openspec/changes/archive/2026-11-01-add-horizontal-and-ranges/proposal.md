# Proposal

## Why

Wide tables keep one measurement per column (monthly rainfall in twelve columns, a
score per judge), and the natural questions run across a row: the total, the warmest
month, whether any value is missing, the first value that is present. Polars answers
them with horizontal functions, which Nanuq lacks: the O'Reilly chapter 9 sections
"Using functions" and "When, then, otherwise" stop on `sum_horizontal`,
`all_horizontal` and `any_horizontal`. Generated columns (`int_range`, `repeat`,
`linear_space`) and correlation (`pl.corr`, which the 0.4 explainer needs to relate El
Niño to world temperature) are missing too.

It is the fifth change of the 0.4 release.

## What Changes

- **Horizontal functions**: `sumHorizontal`, `meanHorizontal` (both with
  `ignoreNulls`), `minHorizontal`, `maxHorizontal`, `allHorizontal`, `anyHorizontal`
  and `coalesce`, taking expressions, literals, selectors or a list of column names.
- **Ranges**: `intRange(start, stop, step, dtype)`, `linearSpace(start, stop,
  numSamples, closed)`, `repeat(value, n)`.
- **Correlation**: `corr(a, b, correlationMethod, propagateNans)` with a
  `CorrelationMethod` pure enum (`Pearson`, `Spearman`), and `cov(a, b, ddof)`.

## Capabilities

### New Capabilities
- `horizontal-functions`: horizontal functions, ranges, correlation.

## Differences from Polars

- `corr`'s method parameter is called `correlationMethod` because `method` is a Nim
  keyword (Python: `method="pearson"`); usually it is passed positionally:
  `corr("a", "b", Spearman)`.
- `sumHorizontal` and `meanHorizontal` take `ignoreNulls` only in the overloads with a
  list (`sumHorizontal([col.a, col.b], ignoreNulls = false)`), because the main
  overload takes any number of arguments.
- `repeat` of a string needs `lit` (`repeat(lit("x"), 3)`): with a plain string, std/strutils'
  `repeat` is chosen.
- `intRange` with one argument counts from 0, as Python's `pl.int_range(n)`.
- Not included: `fold`, `reduce`, `cum_fold` (need Nim callbacks, 0.5), `concat_list`
  (List columns, 0.5), `cum_sum_horizontal` (returns a Struct), `int_ranges`.

## Impact

- `src/rust/src/lib.rs`: `nq_expr_horizontal`, `nq_expr_int_range`,
  `nq_expr_linear_space`, `nq_expr_repeat`, `nq_expr_corr`; `src/nanuq/ffi.nim`,
  `src/nanuq.nim`.
- New `tests/test_horizontal.nim`.
