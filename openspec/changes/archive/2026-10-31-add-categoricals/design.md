# Design

## Nim enums through strings

A Nim enum value crosses the ABI as its string (`$v`): a column is built as strings and
cast to the Enum dtype (`nq_series_cast`), and read back as strings that are mapped to
values with a table built from `for v in T`. Strings, not ordinals, are the stable
identity: holey enums and enums with string values work, and a column read from a file
maps to the Nim type as long as the names match.

## `bool` is a Nim enum

`bool` is an enum in Nim, so the generic overloads use a private type class
`NimEnum = not bool and enum` to keep `bool` on its own paths.

## Categories in dtype specs

`NqDtypeSpec` already carries a categories array for this change; Rust builds
`FrozenCategories` from it for Enum. Reading a column's categories uses two small calls
(count, then one string each) to avoid inventing a string-list ABI.
