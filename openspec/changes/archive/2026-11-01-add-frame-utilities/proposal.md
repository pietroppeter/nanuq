# Proposal

## Why

The 0.4 book ports left a list of smaller Polars functions (BACKLOG.md, "Smaller Polars
functions found by the 0.4 book ports"), and the 0.5 tally of "not yet" book sections adds
a few more: `equals` (7 sections), `upsample` (6), `vstack`/`hstack`/`extend`,
`estimated_size`, `collect_all`, `update`, `meta.*` and `name.to_lowercase`. Each is small.

It is the eighth change of the 0.5 release. It takes up that BACKLOG.md entry.

## What Changes

- Expressions: `over(partitionBy, mappingStrategy)`, `shuffle`, `sample`, `hash`, `get`,
  `argTrue`, `upperBound`, `lowerBound`, `extendConstant`, `rle`, `reshape`;
  `name.toLowercase`, `name.toUppercase`; `e.meta` with `outputName`, `rootNames`,
  `hasMultipleOutputs`, `isColumn`, `isLiteral`, `undoAliases`.
- Frames: `equals` (also on Series), `vstack`, `hstack`, `extend`, `update`, `upsample`,
  `estimatedSize`, `partitionBy(asDict = true)`, and `collectAll` for several LazyFrames.

## Capabilities

### New Capabilities
- `frame-utilities`: the smaller expression and frame functions above.

## Differences from Polars

- `MappingStrategy` is a pure enum (`GroupToRows`, `Join`, `Explode`), not a string.
- `partitionBy(asDict = true)` keys its table by the key values as strings (`@["Biscoe"]`),
  since Nim has no tuples of run-time types; Python keys by tuples of values.
- `hash(seed)` uses one seed for Polars' four (`seed`, `seed_1`, `seed_2`, `seed_3` in
  Python default to it too).
- `estimatedSize` gives bytes as an int; `estimatedSize(unit)` a float in `SizeUnit`.
- `update` supports `how = Left`, `Inner` and `Full` with `on` columns (or the row
  index), as Python does; `includeNulls` is left out.
- `extend` returns a new frame (Nanuq frames are immutable), so it is `vstack`.

## Impact

- `src/rust/src/lib.rs` and `src/nanuq/ffi.nim`: `nq_expr_util`, `nq_expr_reshape`,
  `nq_expr_over_mapping`, `nq_expr_meta_*`, `nq_df_equals`, `nq_df_estimated_size`,
  `nq_df_upsample`, `nq_collect_all`.
- `src/nanuq.nim`; BACKLOG.md entry removed.
- New `tests/test_utilities.nim`.
