# Proposal

## Why

With List columns in Nanuq (add-nested-dtypes) the next step is computing on them. The
book ports use `explode` (11 sections), `list.eval` with `element()` (11), `concat_list`
(6) and `list.first`, `list.get`, `list.len`, `list.sum` (3 to 6 each), and the Polars
coverage map puts the `list` namespace at P1.

It is the second change of the 0.5 release.

## What Changes

- `e.list`, a namespace like `e.str`: aggregations (`len`, `sum`, `min`, `max`, `mean`,
  `median`, `std`, `var`, `first`, `last`, `argMin`, `argMax`, `nUnique`, `any`, `all`),
  access (`get`, `gather`, `gatherEvery`, `slice`, `head`, `tail`, `contains`,
  `countMatches`, `join`), transforms (`sort`, `reverse`, `unique`, `dropNulls`, `diff`,
  `shift`, `sample`, `filter`, `union`, `setDifference`, `setIntersection`,
  `setSymmetricDifference`, `toArray`, `toStruct`), and `eval` and `agg` with `element()`.
- `explode` and `implode` on expressions, `list.explode`, `explode(columns)` on frames
  (eager and lazy, with `emptyAsNull` and `keepNulls`), and `concatList(exprs)`.

## Capabilities

### New Capabilities
- `list-functions`: the list namespace, explode, implode and concatList.

## Differences from Polars

- `list.contains`, `countMatches` and the set operations take a Nim value or an
  expression, as `lit` would turn it.
- `list.sample` takes `n` or `fraction` as overloads (Python has both as keyword arguments).
- `toStruct(fields)` takes the field names; Python also takes a function or a length,
  and its `n_field_strategy` is left out.
- `union` is spelled `union` (Python's `set_union` is an alias for it).
- No `list` namespace on Series yet: use `s.eval(col(s.name).list.len)`.
- `filter(predicate)` is Python's `list.filter`, built on `eval` as in Polars.

## Impact

- `src/rust/src/lib.rs` and `src/nanuq/ffi.nim`: `nq_expr_list` (one entry point with an
  op code, like `nq_expr_str`), `nq_expr_explode`, `nq_expr_implode`, `nq_concat_list`,
  `nq_lf_explode`.
- `src/nanuq.nim`: `ListNameSpace`.
- New `tests/test_lists.nim`.
