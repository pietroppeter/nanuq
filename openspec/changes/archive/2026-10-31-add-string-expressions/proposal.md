# Proposal

## Why

Real tables arrive with messy strings: en dashes in race names ("Paris–Nice"), times
written as "73h 56′ 26″", riders whose names need upper-casing or trimming. Nanuq 0.2 has
no string functions at all, so none of that can be cleaned inside a query. The 0.3
explainer needs `replaceAll`, `extract`, an aggregation that joins a rider's races into
one string, and `format` to print cycling-style gaps.

This change takes up the BACKLOG.md entry "More expressions" (string functions). It is
the fourth change of the 0.3 release, following the dev log "Designing Nanuq 0.3",
section 4 (the `str` namespace as a `distinct Expr`, Rust regex, `literal = true`) and
the later additions confirmed by Pietro on 2026-10-31 (`format`, `str.join`).

## What Changes

- **`e.str`** returns a `StrNameSpace` (a `distinct Expr`) with Polars' string
  functions, in camelCase:
  - `lenChars`, `lenBytes`, `toUppercase`, `toLowercase`, `reverse`;
  - `stripChars`, `stripCharsStart`, `stripCharsEnd` (whitespace, or the given
    characters), `stripPrefix`, `stripSuffix`;
  - `startsWith`, `endsWith`, `contains(pattern, literal = false, strict = true)`,
    `find`, `countMatches`, `extract(pattern, groupIndex = 1)`;
  - `replace(pattern, value, literal = false, n = 1)`, `replaceAll(pattern, value,
    literal = false)`;
  - `slice(offset, length)`, `head(n)`, `tail(n)`, `padStart(length, fillChar = ' ')`,
    `padEnd`, `zfill`;
  - `join(delimiter = "", ignoreNulls = true)`, an aggregation.
  Patterns, lengths and offsets take a Nim value or an expression.
- **`concatStr(exprs, separator = "", ignoreNulls = false)`** and
  **`format("{} ({})", col.rider, col.nat)`**, as Polars' `concat_str` and `format`.
- Polars features `strings`, `regex`, `string_pad`, `string_reverse`, and `concat_str` are
  compiled in.

Not in this change: `split`, `extractAll`, `extractGroups`, `splitExact` (they return
List or Struct columns), `toTitlecase` (needs Polars' nightly feature), `strptime`,
`toDate`, `toDatetime` and `toTime` (the temporal change), `toInteger` (needs Polars' 128-bit
integer dtypes; `cast(int)` parses decimal strings), `normalize`, `json*`,
`encode`/`decode`, `containsAny`/`replaceMany`.

## Capabilities

### New Capabilities
- `strings`: the `str` namespace, `concatStr` and `format`.

### Modified Capabilities
- `native-bridge`: `NqStrOp` joins the enums kept in the same order.

## Differences from Polars

Expected differences from Polars' Rust and Python APIs:

- **Regex syntax** is Rust's `regex` crate, as in both Polars APIs: no backreferences, no
  lookaround.
- **`literal`, `strict`, `n`, `groupIndex`** are named arguments as in Python. Rust's
  `contains_literal`/`find_literal` and `replace_n` become the `literal` and `n`
  arguments.
- **`stripChars()`** without characters strips whitespace, as Python's
  `strip_chars(None)`; Rust takes a null literal.
- **`format`** checks the number of placeholders against the arguments when the
  expression is built, as Python does; it is Nanuq's own proc, built on `concatStr`.
  It overloads `strutils.format`, which takes strings, not expressions.
- **Names** follow Polars in camelCase: `len_chars` → `lenChars`, `strip_chars_start` →
  `stripCharsStart`, `concat_str` → `concatStr`.

## Impact

- `src/rust/src/lib.rs`: `nq_expr_str` (one entry point with `NqStrOp`) and
  `nq_expr_concat_str`; five Polars features in `Cargo.toml`.
- `src/nanuq/ffi.nim`, `src/nanuq.nim`: the declarations, `StrNameSpace` and its procs,
  `concatStr`, `format`.
- `tests/test_strings.nim` (new); README; BACKLOG "More expressions" is removed.
