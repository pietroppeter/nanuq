//! nanuq_ffi: a small C ABI over Polars, consumed by the Nanuq Nim library.
//!
//! Conventions:
//! - Every Polars object (DataFrame, LazyFrame, Expr, Series) crosses the
//!   boundary as an opaque heap pointer. Each one has a `*_free` function.
//! - Functions never consume their pointer arguments: they borrow and clone
//!   (cheap for Polars, columns are Arc'd and lazy plans are trees of Arcs).
//! - On failure, functions return NULL (or false / -1) and store a message
//!   readable with `nq_last_error`.
//! - Strings returned to the caller are owned and must be released with
//!   `nq_string_free`.
//! - Panics are caught and turned into errors, they never unwind into Nim.

use std::cell::RefCell;
use std::ffi::{c_char, CStr, CString};
use std::fs::File;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::path::PathBuf;
use std::ptr;

use polars::prelude::*;

// ---------------------------------------------------------------------------
// Error handling
// ---------------------------------------------------------------------------

thread_local! {
    static LAST_ERROR: RefCell<Option<CString>> = const { RefCell::new(None) };
}

fn set_error(msg: impl Into<String>) {
    let msg = msg.into().replace('\0', " ");
    LAST_ERROR.with(|e| *e.borrow_mut() = CString::new(msg).ok());
}

fn clear_error() {
    LAST_ERROR.with(|e| *e.borrow_mut() = None);
}

/// Runs `f`, catching both `Err` results and panics. Returns `None` on failure
/// after recording the error message.
fn guard<T>(f: impl FnOnce() -> Result<T, String>) -> Option<T> {
    clear_error();
    match catch_unwind(AssertUnwindSafe(f)) {
        Ok(Ok(v)) => Some(v),
        Ok(Err(msg)) => {
            set_error(msg);
            None
        }
        Err(panic) => {
            let msg = panic
                .downcast_ref::<&str>()
                .map(|s| s.to_string())
                .or_else(|| panic.downcast_ref::<String>().cloned())
                .unwrap_or_else(|| "unknown panic".to_string());
            set_error(format!("panic in polars: {msg}"));
            None
        }
    }
}

fn boxed<T>(v: Option<T>) -> *mut T {
    v.map_or(ptr::null_mut(), |v| Box::into_raw(Box::new(v)))
}

fn pe(e: PolarsError) -> String {
    e.to_string()
}

unsafe fn cstr<'a>(s: *const c_char) -> Result<&'a str, String> {
    if s.is_null() {
        return Err("unexpected NULL string".into());
    }
    CStr::from_ptr(s)
        .to_str()
        .map_err(|e| format!("invalid UTF-8: {e}"))
}

unsafe fn borrow<'a, T>(p: *const T, what: &str) -> Result<&'a T, String> {
    p.as_ref().ok_or_else(|| format!("unexpected NULL {what}"))
}

unsafe fn slice<'a, T>(p: *const T, len: usize) -> Result<&'a [T], String> {
    if len == 0 {
        Ok(&[])
    } else if p.is_null() {
        Err("unexpected NULL array".into())
    } else {
        Ok(std::slice::from_raw_parts(p, len))
    }
}

unsafe fn exprs(p: *const *const Expr, len: usize) -> Result<Vec<Expr>, String> {
    slice(p, len)?
        .iter()
        .map(|e| borrow(*e, "expression").cloned())
        .collect()
}

fn to_c_string(s: String) -> *mut c_char {
    CString::new(s.replace('\0', " "))
        .map(CString::into_raw)
        .unwrap_or(ptr::null_mut())
}

/// Last error message on this thread, or NULL. Borrowed: valid until the next
/// nanuq call on the same thread. Do not free.
#[no_mangle]
pub extern "C" fn nq_last_error() -> *const c_char {
    LAST_ERROR.with(|e| e.borrow().as_ref().map_or(ptr::null(), |s| s.as_ptr()))
}

#[no_mangle]
pub unsafe extern "C" fn nq_string_free(s: *mut c_char) {
    if !s.is_null() {
        drop(CString::from_raw(s));
    }
}

/// Version of the nanuq_ffi crate (static string, do not free).
#[no_mangle]
pub extern "C" fn nq_version() -> *const c_char {
    concat!(env!("CARGO_PKG_VERSION"), "\0").as_ptr() as *const c_char
}

// ---------------------------------------------------------------------------
// Series (only used as building blocks for DataFrames)
// ---------------------------------------------------------------------------

#[no_mangle]
pub unsafe extern "C" fn nq_series_free(s: *mut Series) {
    if !s.is_null() {
        drop(Box::from_raw(s));
    }
}

#[no_mangle]
pub unsafe extern "C" fn nq_series_new_i64(
    name: *const c_char,
    data: *const i64,
    len: usize,
) -> *mut Series {
    boxed(guard(|| Ok(Series::new(cstr(name)?.into(), slice(data, len)?))))
}

#[no_mangle]
pub unsafe extern "C" fn nq_series_new_f64(
    name: *const c_char,
    data: *const f64,
    len: usize,
) -> *mut Series {
    boxed(guard(|| Ok(Series::new(cstr(name)?.into(), slice(data, len)?))))
}

#[no_mangle]
pub unsafe extern "C" fn nq_series_new_bool(
    name: *const c_char,
    data: *const bool,
    len: usize,
) -> *mut Series {
    boxed(guard(|| Ok(Series::new(cstr(name)?.into(), slice(data, len)?))))
}

#[no_mangle]
pub unsafe extern "C" fn nq_series_new_str(
    name: *const c_char,
    data: *const *const c_char,
    len: usize,
) -> *mut Series {
    boxed(guard(|| {
        let values = slice(data, len)?
            .iter()
            .map(|s| cstr(*s))
            .collect::<Result<Vec<&str>, _>>()?;
        Ok(Series::new(cstr(name)?.into(), values))
    }))
}

/// Builds `Option`s from values and a validity mask (`valid[i] == false` is null).
unsafe fn with_validity<'a, T: Copy>(
    data: *const T,
    valid: *const bool,
    len: usize,
) -> Result<Vec<Option<T>>, String> {
    let (data, valid) = (slice(data, len)?, slice(valid, len)?);
    Ok(data.iter().zip(valid).map(|(v, ok)| ok.then_some(*v)).collect())
}

#[no_mangle]
pub unsafe extern "C" fn nq_series_new_i64_opt(
    name: *const c_char,
    data: *const i64,
    valid: *const bool,
    len: usize,
) -> *mut Series {
    boxed(guard(|| Ok(Series::new(cstr(name)?.into(), with_validity(data, valid, len)?))))
}

#[no_mangle]
pub unsafe extern "C" fn nq_series_new_f64_opt(
    name: *const c_char,
    data: *const f64,
    valid: *const bool,
    len: usize,
) -> *mut Series {
    boxed(guard(|| Ok(Series::new(cstr(name)?.into(), with_validity(data, valid, len)?))))
}

#[no_mangle]
pub unsafe extern "C" fn nq_series_new_bool_opt(
    name: *const c_char,
    data: *const bool,
    valid: *const bool,
    len: usize,
) -> *mut Series {
    boxed(guard(|| Ok(Series::new(cstr(name)?.into(), with_validity(data, valid, len)?))))
}

/// `data[i]` may be NULL where `valid[i]` is false.
#[no_mangle]
pub unsafe extern "C" fn nq_series_new_str_opt(
    name: *const c_char,
    data: *const *const c_char,
    valid: *const bool,
    len: usize,
) -> *mut Series {
    boxed(guard(|| {
        let values = slice(data, len)?
            .iter()
            .zip(slice(valid, len)?)
            .map(|(s, ok)| if *ok { cstr(*s).map(Some) } else { Ok(None) })
            .collect::<Result<Vec<Option<&str>>, _>>()?;
        Ok(Series::new(cstr(name)?.into(), values))
    }))
}

// ---------------------------------------------------------------------------
// DataFrame
// ---------------------------------------------------------------------------

#[no_mangle]
pub unsafe extern "C" fn nq_df_free(df: *mut DataFrame) {
    if !df.is_null() {
        drop(Box::from_raw(df));
    }
}

/// Builds a DataFrame from `n` series (they are cloned, caller still owns them).
#[no_mangle]
pub unsafe extern "C" fn nq_df_new(series: *const *const Series, n: usize) -> *mut DataFrame {
    boxed(guard(|| {
        let cols = slice(series, n)?
            .iter()
            .map(|s| borrow(*s, "series").map(|s| s.clone().into_column()))
            .collect::<Result<Vec<_>, _>>()?;
        DataFrame::new_infer_height(cols).map_err(pe)
    }))
}

/// Reads a CSV with a header row. The `n` strings in `null_values` are read as
/// null in every column; with `n == 0` only empty fields are.
#[no_mangle]
pub unsafe extern "C" fn nq_df_read_csv(
    path: *const c_char,
    null_values: *const *const c_char,
    n: usize,
) -> *mut DataFrame {
    boxed(guard(|| {
        let path = PathBuf::from(cstr(path)?);
        let nulls = slice(null_values, n)?
            .iter()
            .map(|s| cstr(*s).map(PlSmallStr::from))
            .collect::<Result<Vec<_>, _>>()?;
        let nulls = (!nulls.is_empty()).then(|| NullValues::AllColumns(nulls));
        CsvReadOptions::default()
            .with_has_header(true)
            .map_parse_options(|o| o.with_null_values(nulls.clone()))
            .try_into_reader_with_file_path(Some(path))
            .map_err(pe)?
            .finish()
            .map_err(pe)
    }))
}

#[no_mangle]
pub unsafe extern "C" fn nq_df_write_csv(df: *const DataFrame, path: *const c_char) -> bool {
    guard(|| {
        let mut df = borrow(df, "DataFrame")?.clone();
        let mut file = File::create(cstr(path)?).map_err(|e| e.to_string())?;
        CsvWriter::new(&mut file).finish(&mut df).map_err(pe)
    })
    .is_some()
}

#[no_mangle]
pub unsafe extern "C" fn nq_df_height(df: *const DataFrame) -> i64 {
    guard(|| Ok(borrow(df, "DataFrame")?.height() as i64)).unwrap_or(-1)
}

#[no_mangle]
pub unsafe extern "C" fn nq_df_width(df: *const DataFrame) -> i64 {
    guard(|| Ok(borrow(df, "DataFrame")?.width() as i64)).unwrap_or(-1)
}

/// Pretty-printed table, as Polars displays it.
#[no_mangle]
pub unsafe extern "C" fn nq_df_to_string(df: *const DataFrame) -> *mut c_char {
    guard(|| Ok(to_c_string(format!("{}", borrow(df, "DataFrame")?)))).unwrap_or(ptr::null_mut())
}

#[no_mangle]
pub unsafe extern "C" fn nq_df_head(df: *const DataFrame, n: usize) -> *mut DataFrame {
    boxed(guard(|| Ok(borrow(df, "DataFrame")?.head(Some(n)))))
}

#[no_mangle]
pub unsafe extern "C" fn nq_df_column_name(df: *const DataFrame, idx: usize) -> *mut c_char {
    guard(|| {
        let names = borrow(df, "DataFrame")?.get_column_names();
        names
            .get(idx)
            .map(|n| to_c_string(n.to_string()))
            .ok_or_else(|| format!("column index {idx} out of bounds"))
    })
    .unwrap_or(ptr::null_mut())
}

/// Data type of a column, as a string such as "i64", "f64", "str".
#[no_mangle]
pub unsafe extern "C" fn nq_df_column_dtype(df: *const DataFrame, name: *const c_char) -> *mut c_char {
    guard(|| {
        let col = borrow(df, "DataFrame")?.column(cstr(name)?).map_err(pe)?;
        Ok(to_c_string(col.dtype().to_string()))
    })
    .unwrap_or(ptr::null_mut())
}

fn cell<'a>(df: &'a DataFrame, name: &str, row: usize) -> Result<AnyValue<'a>, String> {
    df.column(name).map_err(pe)?.get(row).map_err(pe)
}

/// Reads one cell as i64 (casting integers). Returns false on error or null.
#[no_mangle]
pub unsafe extern "C" fn nq_df_get_i64(
    df: *const DataFrame,
    name: *const c_char,
    row: usize,
    out: *mut i64,
) -> bool {
    guard(|| {
        let name = cstr(name)?;
        let v = cell(borrow(df, "DataFrame")?, name, row)?;
        let x = v
            .extract::<i64>()
            .ok_or_else(|| format!("cannot read {v} in column '{name}' row {row} as int64"))?;
        *out = x;
        Ok(())
    })
    .is_some()
}

/// Reads one cell as f64 (casting numbers). Returns false on error or null.
#[no_mangle]
pub unsafe extern "C" fn nq_df_get_f64(
    df: *const DataFrame,
    name: *const c_char,
    row: usize,
    out: *mut f64,
) -> bool {
    guard(|| {
        let name = cstr(name)?;
        let v = cell(borrow(df, "DataFrame")?, name, row)?;
        let x = v
            .extract::<f64>()
            .ok_or_else(|| format!("cannot read {v} in column '{name}' row {row} as float64"))?;
        *out = x;
        Ok(())
    })
    .is_some()
}

/// Reads one cell as a string (any dtype, via its display form; strings are
/// returned without quotes). Free with `nq_string_free`.
/// Reads one boolean cell. Returns false on error or null.
#[no_mangle]
pub unsafe extern "C" fn nq_df_get_bool(
    df: *const DataFrame,
    name: *const c_char,
    row: usize,
    out: *mut bool,
) -> bool {
    guard(|| {
        let name = cstr(name)?;
        match cell(borrow(df, "DataFrame")?, name, row)? {
            AnyValue::Boolean(b) => {
                *out = b;
                Ok(())
            }
            v => Err(format!("cannot read {v} in column '{name}' row {row} as bool")),
        }
    })
    .is_some()
}

#[no_mangle]
pub unsafe extern "C" fn nq_df_get_str(
    df: *const DataFrame,
    name: *const c_char,
    row: usize,
) -> *mut c_char {
    guard(|| {
        let name = cstr(name)?;
        let v = cell(borrow(df, "DataFrame")?, name, row)?;
        let s = match v {
            AnyValue::Null => return Err(format!("cannot read null in column '{name}' row {row} as string")),
            AnyValue::String(s) => s.to_string(),
            AnyValue::StringOwned(s) => s.to_string(),
            other => other.to_string(),
        };
        Ok(to_c_string(s))
    })
    .unwrap_or(ptr::null_mut())
}

// ---------------------------------------------------------------------------
// Whole columns and nulls
// ---------------------------------------------------------------------------

#[no_mangle]
pub unsafe extern "C" fn nq_df_null_count(df: *const DataFrame, name: *const c_char) -> i64 {
    guard(|| {
        let col = borrow(df, "DataFrame")?.column(cstr(name)?).map_err(pe)?;
        Ok(col.null_count() as i64)
    })
    .unwrap_or(-1)
}

#[no_mangle]
pub unsafe extern "C" fn nq_df_cell_is_null(
    df: *const DataFrame,
    name: *const c_char,
    row: usize,
    out: *mut bool,
) -> bool {
    guard(|| {
        *out = cell(borrow(df, "DataFrame")?, cstr(name)?, row)?.is_null();
        Ok(())
    })
    .is_some()
}

/// Reads column `name` cast to `to`, after checking that its dtype is allowed.
/// Errors name the column and its dtype.
unsafe fn column_as(
    df: *const DataFrame,
    name: *const c_char,
    len: usize,
    to: DataType,
    allowed: fn(&DataType) -> bool,
) -> Result<Series, String> {
    let name = cstr(name)?;
    let col = borrow(df, "DataFrame")?.column(name).map_err(pe)?;
    if !allowed(col.dtype()) {
        return Err(format!("cannot read column '{name}' of type {} as {to}", col.dtype()));
    }
    if col.len() != len {
        return Err(format!("column '{name}' has {} rows, buffer has {len}", col.len()));
    }
    Ok(col.cast(&to).map_err(pe)?.as_materialized_series().clone())
}

/// Fills caller-allocated `values` and `valid` (both `len` long) in one pass.
/// Null slots get a default value and `valid[i] = false`.
unsafe fn fill<T: Copy + Default>(
    it: impl Iterator<Item = Option<T>>,
    values: *mut T,
    valid: *mut bool,
    len: usize,
) -> Result<(), String> {
    if len > 0 && (values.is_null() || valid.is_null()) {
        return Err("unexpected NULL buffer".into());
    }
    for (i, v) in it.take(len).enumerate() {
        *values.add(i) = v.unwrap_or_default();
        *valid.add(i) = v.is_some();
    }
    Ok(())
}

/// Integer columns only (no silent truncation of floats).
#[no_mangle]
pub unsafe extern "C" fn nq_df_column_i64(
    df: *const DataFrame,
    name: *const c_char,
    values: *mut i64,
    valid: *mut bool,
    len: usize,
) -> bool {
    guard(|| {
        let s = column_as(df, name, len, DataType::Int64, |d| d.is_integer())?;
        fill(s.i64().map_err(pe)?.iter(), values, valid, len)
    })
    .is_some()
}

/// Integer and float columns.
#[no_mangle]
pub unsafe extern "C" fn nq_df_column_f64(
    df: *const DataFrame,
    name: *const c_char,
    values: *mut f64,
    valid: *mut bool,
    len: usize,
) -> bool {
    guard(|| {
        let s = column_as(df, name, len, DataType::Float64, |d| d.is_primitive_numeric())?;
        fill(s.f64().map_err(pe)?.iter(), values, valid, len)
    })
    .is_some()
}

#[no_mangle]
pub unsafe extern "C" fn nq_df_column_bool(
    df: *const DataFrame,
    name: *const c_char,
    values: *mut bool,
    valid: *mut bool,
    len: usize,
) -> bool {
    guard(|| {
        let s = column_as(df, name, len, DataType::Boolean, |d| d.is_bool())?;
        fill(s.bool().map_err(pe)?.iter(), values, valid, len)
    })
    .is_some()
}

/// Total UTF-8 bytes of column `name` read as strings (any dtype), or -1.
#[no_mangle]
pub unsafe extern "C" fn nq_df_column_str_size(df: *const DataFrame, name: *const c_char) -> i64 {
    guard(|| {
        let len = borrow(df, "DataFrame")?.height();
        let s = column_as(df, name, len, DataType::String, |_| true)?;
        Ok(s.str().map_err(pe)?.iter().map(|v| v.map_or(0, str::len)).sum::<usize>() as i64)
    })
    .unwrap_or(-1)
}

/// Writes the column as strings in Arrow's layout: the concatenated bytes in
/// `data` (`data_len` long, from `nq_df_column_str_size`), `len + 1` offsets, and
/// the validity mask. Row i is `data[offsets[i] .. offsets[i + 1]]`.
#[no_mangle]
pub unsafe extern "C" fn nq_df_column_str(
    df: *const DataFrame,
    name: *const c_char,
    data: *mut u8,
    data_len: usize,
    offsets: *mut u64,
    valid: *mut bool,
    len: usize,
) -> bool {
    guard(|| {
        let s = column_as(df, name, len, DataType::String, |_| true)?;
        if offsets.is_null() || (len > 0 && valid.is_null()) || (data_len > 0 && data.is_null()) {
            return Err("unexpected NULL buffer".into());
        }
        let mut pos = 0usize;
        *offsets = 0;
        for (i, v) in s.str().map_err(pe)?.iter().take(len).enumerate() {
            let bytes = v.unwrap_or("").as_bytes();
            if pos + bytes.len() > data_len {
                return Err("string buffer too small".into());
            }
            ptr::copy_nonoverlapping(bytes.as_ptr(), data.add(pos), bytes.len());
            pos += bytes.len();
            *offsets.add(i + 1) = pos as u64;
            *valid.add(i) = v.is_some();
        }
        Ok(())
    })
    .is_some()
}

// ---------------------------------------------------------------------------
// Expressions
// ---------------------------------------------------------------------------

#[no_mangle]
pub unsafe extern "C" fn nq_expr_free(e: *mut Expr) {
    if !e.is_null() {
        drop(Box::from_raw(e));
    }
}

#[no_mangle]
pub unsafe extern "C" fn nq_expr_col(name: *const c_char) -> *mut Expr {
    boxed(guard(|| Ok(col(cstr(name)?))))
}

#[no_mangle]
pub extern "C" fn nq_expr_lit_i64(v: i64) -> *mut Expr {
    boxed(Some(lit(v)))
}

#[no_mangle]
pub extern "C" fn nq_expr_lit_f64(v: f64) -> *mut Expr {
    boxed(Some(lit(v)))
}

#[no_mangle]
pub extern "C" fn nq_expr_lit_bool(v: bool) -> *mut Expr {
    boxed(Some(lit(v)))
}

#[no_mangle]
pub unsafe extern "C" fn nq_expr_lit_str(v: *const c_char) -> *mut Expr {
    boxed(guard(|| Ok(lit(cstr(v)?.to_string()))))
}

/// Binary operators. Keep in sync with `NqBinOp` in nanuq/ffi.nim.
#[repr(C)]
#[derive(Clone, Copy)]
pub enum NqBinOp {
    Add = 0,
    Sub,
    Mul,
    Div,
    Eq,
    NotEq,
    Lt,
    LtEq,
    Gt,
    GtEq,
    And,
    Or,
}

#[no_mangle]
pub unsafe extern "C" fn nq_expr_binary(a: *const Expr, op: NqBinOp, b: *const Expr) -> *mut Expr {
    boxed(guard(|| {
        let a = borrow(a, "expression")?.clone();
        let b = borrow(b, "expression")?.clone();
        Ok(match op {
            NqBinOp::Add => a + b,
            NqBinOp::Sub => a - b,
            NqBinOp::Mul => a * b,
            NqBinOp::Div => a / b,
            NqBinOp::Eq => a.eq(b),
            NqBinOp::NotEq => a.neq(b),
            NqBinOp::Lt => a.lt(b),
            NqBinOp::LtEq => a.lt_eq(b),
            NqBinOp::Gt => a.gt(b),
            NqBinOp::GtEq => a.gt_eq(b),
            NqBinOp::And => a.and(b),
            NqBinOp::Or => a.or(b),
        })
    }))
}

/// Unary functions and aggregations. Keep in sync with `NqUnary` in
/// nanuq/ffi.nim.
#[repr(C)]
#[derive(Clone, Copy)]
pub enum NqUnary {
    Not = 0,
    Sum,
    Mean,
    Min,
    Max,
    Count,
    First,
    Last,
    NUnique,
    Std,
    IsNull,
    IsNotNull,
}

#[no_mangle]
pub unsafe extern "C" fn nq_expr_unary(e: *const Expr, op: NqUnary) -> *mut Expr {
    boxed(guard(|| {
        let e = borrow(e, "expression")?.clone();
        Ok(match op {
            NqUnary::Not => e.not(),
            NqUnary::Sum => e.sum(),
            NqUnary::Mean => e.mean(),
            NqUnary::Min => e.min(),
            NqUnary::Max => e.max(),
            NqUnary::Count => e.count(),
            NqUnary::First => e.first(),
            NqUnary::Last => e.last(),
            NqUnary::NUnique => e.n_unique(),
            NqUnary::Std => e.std(1),
            NqUnary::IsNull => e.is_null(),
            NqUnary::IsNotNull => e.is_not_null(),
        })
    }))
}

#[no_mangle]
pub unsafe extern "C" fn nq_expr_fill_null(e: *const Expr, value: *const Expr) -> *mut Expr {
    boxed(guard(|| {
        let value = borrow(value, "expression")?.clone();
        Ok(borrow(e, "expression")?.clone().fill_null(value))
    }))
}

#[no_mangle]
pub unsafe extern "C" fn nq_expr_alias(e: *const Expr, name: *const c_char) -> *mut Expr {
    boxed(guard(|| Ok(borrow(e, "expression")?.clone().alias(cstr(name)?))))
}

#[no_mangle]
pub unsafe extern "C" fn nq_expr_to_string(e: *const Expr) -> *mut c_char {
    guard(|| Ok(to_c_string(format!("{}", borrow(e, "expression")?)))).unwrap_or(ptr::null_mut())
}

// ---------------------------------------------------------------------------
// LazyFrame
// ---------------------------------------------------------------------------

#[no_mangle]
pub unsafe extern "C" fn nq_lf_free(lf: *mut LazyFrame) {
    if !lf.is_null() {
        drop(Box::from_raw(lf));
    }
}

#[no_mangle]
pub unsafe extern "C" fn nq_df_lazy(df: *const DataFrame) -> *mut LazyFrame {
    boxed(guard(|| Ok(borrow(df, "DataFrame")?.clone().lazy())))
}

unsafe fn lf<'a>(p: *const LazyFrame) -> Result<LazyFrame, String> {
    borrow(p, "LazyFrame").cloned()
}

#[no_mangle]
pub unsafe extern "C" fn nq_lf_collect(lf_: *const LazyFrame) -> *mut DataFrame {
    boxed(guard(|| lf(lf_)?.collect().map_err(pe)))
}

#[no_mangle]
pub unsafe extern "C" fn nq_lf_select(
    lf_: *const LazyFrame,
    e: *const *const Expr,
    n: usize,
) -> *mut LazyFrame {
    boxed(guard(|| Ok(lf(lf_)?.select(exprs(e, n)?))))
}

#[no_mangle]
pub unsafe extern "C" fn nq_lf_with_columns(
    lf_: *const LazyFrame,
    e: *const *const Expr,
    n: usize,
) -> *mut LazyFrame {
    boxed(guard(|| Ok(lf(lf_)?.with_columns(exprs(e, n)?))))
}

#[no_mangle]
pub unsafe extern "C" fn nq_lf_filter(lf_: *const LazyFrame, predicate: *const Expr) -> *mut LazyFrame {
    boxed(guard(|| {
        Ok(lf(lf_)?.filter(borrow(predicate, "expression")?.clone()))
    }))
}

#[no_mangle]
pub unsafe extern "C" fn nq_lf_group_by_agg(
    lf_: *const LazyFrame,
    by: *const *const Expr,
    nby: usize,
    aggs: *const *const Expr,
    naggs: usize,
) -> *mut LazyFrame {
    boxed(guard(|| {
        Ok(lf(lf_)?
            .group_by_stable(exprs(by, nby)?)
            .agg(exprs(aggs, naggs)?))
    }))
}

#[no_mangle]
pub unsafe extern "C" fn nq_lf_sort(
    lf_: *const LazyFrame,
    by: *const c_char,
    descending: bool,
) -> *mut LazyFrame {
    boxed(guard(|| {
        let opts = SortMultipleOptions::default().with_order_descending(descending);
        Ok(lf(lf_)?.sort([cstr(by)?], opts))
    }))
}

/// Drops rows with a null in any of the `n` named columns, or in any column
/// when `n == 0`.
#[no_mangle]
pub unsafe extern "C" fn nq_lf_drop_nulls(
    lf_: *const LazyFrame,
    names: *const *const c_char,
    n: usize,
) -> *mut LazyFrame {
    boxed(guard(|| {
        let names = slice(names, n)?
            .iter()
            .map(|s| cstr(*s))
            .collect::<Result<Vec<_>, _>>()?;
        let subset = (!names.is_empty()).then(|| cols(names));
        Ok(lf(lf_)?.drop_nulls(subset))
    }))
}

#[no_mangle]
pub unsafe extern "C" fn nq_lf_limit(lf_: *const LazyFrame, n: u32) -> *mut LazyFrame {
    boxed(guard(|| Ok(lf(lf_)?.limit(n.into()))))
}

/// The optimized query plan, as text.
#[no_mangle]
pub unsafe extern "C" fn nq_lf_explain(lf_: *const LazyFrame) -> *mut c_char {
    guard(|| Ok(to_c_string(lf(lf_)?.explain(true).map_err(pe)?))).unwrap_or(ptr::null_mut())
}
