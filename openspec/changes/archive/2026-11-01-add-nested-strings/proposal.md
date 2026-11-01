# Proposal

## Why

Nanuq 0.3 left out the string functions that return lists or structs: `str.split`
alone blocks 12 book sections, `extract_all` 3, `split_exact` 2, and `json_decode` is how
JSON in a string column becomes structs. With nested types in place
(add-nested-dtypes), they can come in.

It is the third change of the 0.5 release.

## What Changes

- `str.split(by, inclusive)` and `str.extractAll(pattern)` give `list[str]`;
  `str.splitExact(by, n, inclusive)`, `str.splitn(by, n)` and
  `str.extractGroups(pattern)` give structs (fields `field_0`, ... or the regex groups).
- Matching many literal patterns at once (Aho-Corasick, as in Polars):
  `str.containsAny(patterns)`, `str.replaceMany(patterns, replaceWith)` (also from a
  mapping `{"a": "x"}`), `str.extractMany(patterns)` and `str.findMany(patterns)`.
- JSON in strings: `str.jsonDecode(dtype)` (or a Nim type) and `str.jsonPathMatch(path)`.

## Capabilities

### Modified Capabilities
- `strings`: string functions that return lists and structs.

## Differences from Polars

- `jsonDecode` needs the data type, as Polars' `Expr.str.json_decode` does; Python's
  `Series.str.json_decode` infers it, Nanuq does not (there are no Series namespaces).
- Patterns are a Nim array of strings, or an expression giving a list.

## Impact

- `src/rust/src/lib.rs` and `src/nanuq/ffi.nim`: `nq_expr_str_nested` with an op code.
- `src/nanuq.nim`: methods on `StrNameSpace`.
- Tests in `tests/test_strings.nim`.
