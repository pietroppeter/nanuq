# native-bridge Specification

## Purpose
How Nanuq reaches Polars: a Rust crate (`rust/`, `nanuq_ffi`) exports a C ABI, it is
linked as a static library, and `src/nanuq/ffi.nim` declares it to Nim.

## Requirements

### Requirement: C ABI over Polars with opaque handles
The `nanuq_ffi` crate SHALL expose Polars objects (DataFrame, LazyFrame, Expr, Series)
only as opaque heap pointers through `extern "C"` functions, each type with a matching
`*_free` function. Functions SHALL borrow their pointer arguments and return newly
allocated objects.

#### Scenario: Ownership stays with the caller
- **WHEN** Nim passes a DataFrame pointer to an FFI function
- **THEN** the pointer stays valid and owned by Nim after the call
- **AND** any object the function returns is a new pointer that Nim must free exactly once

### Requirement: Errors and panics never cross the boundary
Every FFI function SHALL catch Polars errors and Rust panics, signal failure with a NULL
(or false / -1) return, and make the message available through `nq_last_error`.

#### Scenario: Polars error
- **WHEN** an operation fails in Polars (e.g. a missing column)
- **THEN** the function returns NULL and `nq_last_error` returns the Polars message

#### Scenario: Rust panic
- **WHEN** Polars panics inside an FFI call
- **THEN** the panic is caught, the call returns NULL, and no unwinding reaches Nim

### Requirement: Nim declarations mirror the C ABI
`src/nanuq/ffi.nim` SHALL declare every exported function with matching signatures, and
the enums `NqBinOp` and `NqUnary` SHALL keep the same order as in Rust.

#### Scenario: ABI change
- **WHEN** a function is added or changed in `rust/src/lib.rs`
- **THEN** `src/nanuq/ffi.nim` is updated in the same change

### Requirement: Linking the static library
Importing `nanuq` SHALL link `libnanuq_ffi.a` from `rust/target/release`, or from
`-d:nanuqLibDir`, and SHALL build it with cargo at compile time when it is missing,
unless `-d:nanuqNoCargo` is defined.

#### Scenario: Library missing, cargo allowed
- **WHEN** the library file does not exist and `nanuqNoCargo` is not defined
- **THEN** compilation runs `cargo build --release` for `rust/` and links the result

#### Scenario: Library missing, cargo disabled
- **WHEN** the library file does not exist and `-d:nanuqNoCargo` is defined
- **THEN** compilation fails with an error naming the expected library path

### Requirement: Columns cross in bulk
Reading a whole column into Nim SHALL take a constant number of FFI calls, independent
of the number of rows, and SHALL transfer a validity mask alongside the values so
nulls are not lost or replaced by placeholder values.

#### Scenario: Large column
- **WHEN** a 1,000,000-row float column is read into a Nim seq
- **THEN** at most two FFI calls are made for that column

#### Scenario: Validity
- **WHEN** a column with nulls crosses the boundary
- **THEN** Nim receives, for every row, whether the value is valid
