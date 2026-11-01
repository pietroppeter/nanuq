# Proposal

## Why

Many string columns hold a few distinct values: a team, a nationality, a medal, one of
the five Monuments. Polars stores them as Categorical (categories found in the data) or
Enum (a fixed, ordered set), which is smaller, faster to group and join, and for Enum
sorts in a meaningful order. Nim already has the right tool for a fixed set of names,
the `enum`, so Nanuq can map one to the other: the 0.3 explainer uses
`type Monument = enum` to sort races in calendar order.

This change takes up the categoricals part of BACKLOG.md "More dtypes", following the
dev log "Designing Nanuq 0.3" (categoricals moved into 0.3 by Pietro on 2026-10-31). It
is the seventh change of the 0.3 release.

## What Changes

- **Data types**: `DataTypeKind` gains `Categorical` and `Enum`. `Categorical` is a
  `DataType` constant; Enum values carry their `categories`. `$` gives Polars' names
  `cat` and `enum`.
- **`Enum(["low", "high"])`** builds an Enum dtype at run time (duplicates raise
  `ValueError`).
- **Nim enums are Polars Enums**: `dataType(Medal)` is the Enum of `$` of each value in
  order, so `cast(Medal)`, `series("m", [Gold, Silver])`, the block form of
  `newDataFrame`, `toList(df, "m", Medal)` and `df["m", i, Medal]` work, `Option`-wrapped
  for nulls. Enum values can be compared with columns (`col.medal == Gold`) and used in
  `isIn`. Reading a value that is not in the Nim enum raises `InvalidOperationError`.
- **`e.cat`** returns a `CatNameSpace` (a `distinct Expr`) with `getCategories`,
  `lenBytes`, `lenChars`, `startsWith`, `endsWith` and `slice`.
- **`e.toPhysical`** gives the physical values (category indices, days, integers).
- `describe` reports no min and max for Categorical and Enum columns, as Python does.
- The Polars feature `dtype-categorical` (already compiled in) is used.

Not in this change: lexical ordering of Categoricals (`Categorical("lexical")`), local
vs global category scopes (`StringCache`), `cat.toLocal`, appending to an Enum's
categories.

## Capabilities

### New Capabilities
- `categoricals`: Categorical and Enum columns, Nim enums, and the `cat` namespace.

### Modified Capabilities
- `data-types`: the two kinds, `categories`, and Nim enums in `dataType`.
- `native-bridge`: `NqCatOp` joins the ordered enums.

## Differences from Polars

Expected differences from Polars' Rust and Python APIs:

- **Nim enums** have no Python or Rust counterpart as a dtype; Python accepts a Python
  `enum.Enum` class as `pl.Enum(MyEnum)`, which is close. Nanuq uses `$` of each value,
  so enums with string values (`Flanders = "Ronde van Vlaanderen"`) name their
  categories freely.
- **`Enum`** is a proc that returns a `DataType` (Python's `pl.Enum([...])` class);
  comparing kinds needs `DataTypeKind.Enum`.
- **`Categorical`** always uses Polars' global categories, as Python's default; there is
  no `ordering` argument.
- **Names** follow Polars in camelCase: `get_categories` → `getCategories`,
  `to_physical` → `toPhysical`.

## Impact

- `src/rust/src/lib.rs`: the two dtype codes, Enum categories from `NqDtypeSpec`,
  `nq_df_column_n_categories`, `nq_df_column_category`, `nq_series_cast` and
  `nq_expr_cat` with `NqCatOp`.
- `src/nanuq/ffi.nim`, `src/nanuq.nim`: the declarations, the `DataType` changes, enum
  overloads, `CatNameSpace` and `toPhysical`.
- `tests/test_categorical.nim` (new); README; BACKLOG "More dtypes" drops categoricals.
