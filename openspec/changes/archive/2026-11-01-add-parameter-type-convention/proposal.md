# Proposal

## Why

0.4 introduced four parameter types with converters (`ColumnNames`, `OptInterval`,
`JoinKey`, `AsofTolerance`) so that calls like `pivot("season", index = "year")` and
`joinAsof(..., tolerance = 7.days)` read like Python. It is a new pattern in the API,
and Pietro asked that it be tracked in the API conventions so later changes follow it.

Part of the 0.4 release (#51).

## What Changes

- api-conventions gains the rule: parameters that take several types, with a default,
  use converter types; the four existing types are listed.
- No code change.

## Capabilities

### Modified Capabilities
- `api-conventions`: the converter parameter type rule.

## Differences from Polars

- None in behaviour. Python accepts these unions dynamically; Nanuq accepts the same
  spellings through converters.

## Impact

- Spec only.
