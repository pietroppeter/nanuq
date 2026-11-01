# Proposal

## Why

Python Polars calls the "which variant" parameter of `rank`, `corr` and `interpolate`
`method`, which is a Nim keyword. Nanuq worked around it three different ways:
`rankMethod`, `correlationMethod` and `interpolation`. The names were long and
inconsistent (Pietro, reviewing the 0.4 dev log: "not a fan of the long name
correlationMethod").

Part of the 0.4 release (#51). There are no users yet, so the rename needs no
deprecation.

## What Changes

- **BREAKING** `rank(rankMethod = ...)` becomes `rank(how = ...)`.
- `corr(a, b, correlationMethod = ...)` becomes `corr(a, b, how = ...)` (new in 0.4).
- `interpolate(interpolation = ...)` becomes `interpolate(how = ...)` (new in 0.4).
- api-conventions gains the rule: Python's `method` is `how` in Nanuq.
- Positional calls (`rank(Min)`, `corr(a, b, Spearman)`) are unchanged.

## Capabilities

### Modified Capabilities
- `api-conventions`: the `method` → `how` rule.
- `expressions`: `rank`'s parameter name.
- `horizontal-functions`: `corr`'s parameter name.
- `missing-values`: `interpolate`'s parameter name.

## Differences from Polars

- Python: `rank(method="dense")`, `pl.corr(a, b, method="spearman")`,
  `interpolate(method="nearest")`. Nanuq: `how = Dense`, `how = Spearman`,
  `how = Nearest`.
- Rust Polars has separate `pearson_corr` and `spearman_rank_corr` functions, and takes
  `RankOptions { method, .. }` and `InterpolationMethod` as plain arguments.
- `quantile` keeps `interpolation`, which is Python's name there.

## Impact

- `src/nanuq.nim`: three parameter names. No ABI change.
- Specs, the 0.4 dev-log post and the CHANGELOG mention the new names.
