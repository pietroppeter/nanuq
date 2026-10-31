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
the enums `NqBinOp`, `NqUnary`, `NqDtype`, `NqJoinType`, `NqJoinValidation`,
`NqMaintainOrderJoin`, `NqConcat` and `NqUniqueKeepStrategy` SHALL keep the same order as
in Rust. `NqDtype` SHALL also keep the order of `DataTypeKind`, and the option enums the
order of their Nim API enums.

#### Scenario: ABI change
- **WHEN** a function is added or changed in `rust/src/lib.rs`
- **THEN** `src/nanuq/ffi.nim` is updated in the same change

### Requirement: Linking the static library
Importing `nanuq` SHALL link `libnanuq_ffi.a` from the first of these sources that has
it: the directory given with `-d:nanuqLibDir`, the local cargo output of the crate in
`src/rust/`, the prebuilt library (see `binary-distribution`), and finally a cargo build
of `src/rust/` run at compile time. `-d:nanuqLib=auto` (the default) allows all
sources. `-d:nanuqLib=prebuilt` (or `-d:nanuqNoCargo`) never runs cargo.
`-d:nanuqLib=source` never downloads. The crate SHALL ship inside the installed
package, so the cargo fallback also works after `nimble install`.

#### Scenario: Library missing, cargo allowed
- **WHEN** no local library exists, no prebuilt library is available, and the policy is
  `auto` or `source`
- **THEN** compilation runs `cargo build --release` for `src/rust/` and links the result

#### Scenario: Library missing, cargo disabled
- **WHEN** no local or prebuilt library is available and the policy is `prebuilt`
- **THEN** compilation fails with an error naming the expected library path and how to
  get one

#### Scenario: Installed with nimble
- **WHEN** a user runs `nimble install nanuq` on a platform without a prebuilt library
  and has cargo
- **THEN** compiling a program that imports `nanuq` builds the library from the
  installed package's sources and links it

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

### Requirement: Library version check
The library SHALL report its version through the C ABI. At startup, Nanuq SHALL compare
it with the lib version it was compiled for and stop with an error naming both versions
if they differ.

#### Scenario: Stale library
- **WHEN** `-d:nanuqLibDir` points at a library built from an older crate version
- **THEN** the program stops at startup with an error naming both versions

### Requirement: Formatted cells
The bridge SHALL return a single cell as text formatted by Polars, as Python Polars'
`get_fmt` does: the value's display form, with strings in quotes and cut to a given
number of characters followed by `…`.

#### Scenario: Float cell
- **WHEN** a cell holding 5076.016260162602 is formatted
- **THEN** the text is the same as in Polars' text table, `5076.01626`

#### Scenario: Long string
- **WHEN** a string of 40 characters is formatted with a limit of 30
- **THEN** the text is a quote, its first 30 characters and `…`
