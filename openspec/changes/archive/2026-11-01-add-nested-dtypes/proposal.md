# Proposal

## Why

Lists, arrays and structs are the Polars data types Nanuq does not model yet. They block
most of the book sections still marked "not yet" (`str.split`, `explode`, `unnest`,
`struct.field`, `list.eval`, `value_counts`, JSON), and the 0.4 changelog lists them as the
main limitation. Before any list or struct function, Nanuq needs the types themselves, and a
way to move nested values between Nim and Polars.

It is the first change of the 0.5 release ("Nested data and user code"). It comes from the
BACKLOG.md entry "More dtypes" (lists and structs; decimals and binary stay there).

## What Changes

- `DataType` gains the kinds `List`, `Array` and `Struct`, with constructors `List(Int64)`,
  `Array(Float64, 3)` (or a shape, `Array(Int64, [2, 3])`) and
  `Struct({"x": Int64, "y": String})`, accessors `inner`, `width`, `shape` and `fields`
  (a seq of `Field`, with `name` and `dtype`), and Polars' names (`list[i64]`,
  `array[f64, 3]`, `struct[2]`). `dataType(T)` maps `seq[T]` to List, `array[N, T]` to
  Array and objects and named tuples to Struct.
- Nested columns from Nim: `series(name, values)` and the `newDataFrame` block take seqs
  of seqs (`@[@[1, 2], @[]]`), arrays, objects and named tuples, at any depth, with
  `Option` (or `nil` in the block) for null rows and `Option` elements for null values.
  `toDataFrame(rows)` takes objects with such fields. `lit(@[1, 2])` is a list literal.
- Nested values back to Nim: `toList(column, seq[int])`, `toList(column, MyObject)`,
  `Option` of these, the same on Series, cell reads `df[column, row, seq[string]]`, and
  row objects (`rows(T)`) whose fields are seqs or objects.
- Casting to nested types: `col("a").cast(List(Int32))`.
- The C ABI passes data types as handles (`NqDataType`), so nested types can be read and
  given at any depth, and builds nested Series from their parts (inner values and offsets,
  or fields).

## Capabilities

### New Capabilities
- `nested-data`: List, Array and Struct data types and nested values between Nim and Polars.

### Modified Capabilities
- `data-types`: the type mapping covers seqs, arrays, objects and tuples.

## Differences from Polars

- Struct values are Nim objects or named tuples, chosen by the caller; Python uses dicts.
  A struct literal in the block is a named tuple, `(x: 1, y: 2.0)`, not `{"x": 1}`.
- `Struct(...)` takes `{"name": dtype}` pairs or a seq of `Field`; Python also takes a
  dict or a list of `pl.Field`, which are the same thing.
- `Array(inner, [2, 3])` takes a shape as an array of ints; Python takes a tuple.
- Reading a struct field that is missing from the object raises `ColumnNotFoundError`
  (as `rows` does for columns); extra struct fields are ignored.
- An empty Nim seq has a static element type, so `@[]` columns are never `list[null]`,
  unlike Python's `pl.Series([[]])`.

## Impact

- C ABI: data type handles (`nq_dtype_*`) replace the per-property column functions;
  `NqDtypeSpec` gains a nested handle; new `nq_series_list_from_parts`,
  `nq_series_array_from_inner`, `nq_series_struct_from_fields` and readers
  `nq_series_list_offsets`, `nq_series_inner`, `nq_series_struct_field`,
  `nq_series_validity`. `src/rust/src/lib.rs` and `src/nanuq/ffi.nim` together.
- `src/nanuq.nim`: types, constructors, generic readers and writers.
- Polars crate features for 0.5 are all added here (list_*, array_*, json, sql, meta, ...).
- New `tests/test_nested.nim`.
