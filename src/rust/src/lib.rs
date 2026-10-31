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

/// Lazily scans a CSV file or glob. `null_values` (n_nulls strings) are read as
/// null in every column; `override_names`/`override_dtypes` (n_overrides each) set
/// column dtypes. `n_rows < 0` reads all rows; `infer_schema_length < 0` infers
/// from all rows.
#[no_mangle]
pub unsafe extern "C" fn nq_lf_scan_csv(
    path: *const c_char,
    separator: u8,
    has_header: bool,
    null_values: *const *const c_char,
    n_nulls: usize,
    override_names: *const *const c_char,
    override_dtypes: *const NqDtype,
    n_overrides: usize,
    skip_rows: usize,
    n_rows: i64,
    infer_schema_length: i64,
    ignore_errors: bool,
    decimal_comma: bool,
) -> *mut LazyFrame {
    boxed(guard(|| {
        let path = cstr(path)?;
        let nulls = names(null_values, n_nulls)?
            .into_iter()
            .map(PlSmallStr::from)
            .collect::<Vec<_>>();
        let nulls = (!nulls.is_empty()).then(|| NullValues::AllColumns(nulls));
        let onames = names(override_names, n_overrides)?;
        let odtypes = slice(override_dtypes, n_overrides)?;
        let overrides = if n_overrides == 0 {
            None
        } else {
            let fields = onames
                .iter()
                .zip(odtypes)
                .map(|(n, d)| Ok(Field::new((*n).into(), dtype_from_code(*d)?)))
                .collect::<Result<Vec<_>, String>>()?;
            Some(Arc::new(Schema::from_iter(fields)))
        };
        let opt = |v: i64| (v >= 0).then_some(v as usize);
        LazyCsvReader::new(PlRefPath::from(path))
            .with_separator(separator)
            .with_has_header(has_header)
            .with_null_values(nulls)
            .with_dtype_overwrite(overrides)
            .with_skip_rows(skip_rows)
            .with_n_rows(opt(n_rows))
            .with_infer_schema_length(opt(infer_schema_length))
            .with_ignore_errors(ignore_errors)
            .with_decimal_comma(decimal_comma)
            .finish()
            .map_err(pe)
    }))
}

/// Quote styles for `nq_df_write_csv`. Same order as Nim's `QuoteStyle`.
#[repr(C)]
#[derive(Clone, Copy)]
pub enum NqQuoteStyle {
    Necessary = 0,
    Always,
    NonNumeric,
    Never,
}

/// Writes a CSV file. `float_precision < 0` keeps full precision.
#[no_mangle]
pub unsafe extern "C" fn nq_df_write_csv(
    df: *const DataFrame,
    path: *const c_char,
    separator: u8,
    include_header: bool,
    null_value: *const c_char,
    quote_style: NqQuoteStyle,
    float_precision: i32,
    decimal_comma: bool,
) -> bool {
    guard(|| {
        let mut df = borrow(df, "DataFrame")?.clone();
        let null_value = cstr(null_value)?;
        let quote_style = match quote_style {
            NqQuoteStyle::Necessary => QuoteStyle::Necessary,
            NqQuoteStyle::Always => QuoteStyle::Always,
            NqQuoteStyle::NonNumeric => QuoteStyle::NonNumeric,
            NqQuoteStyle::Never => QuoteStyle::Never,
        };
        let mut file = File::create(cstr(path)?).map_err(|e| e.to_string())?;
        CsvWriter::new(&mut file)
            .with_separator(separator)
            .include_header(include_header)
            .with_null_value(null_value.into())
            .with_quote_style(quote_style)
            .with_float_precision((float_precision >= 0).then_some(float_precision as usize))
            .with_decimal_comma(decimal_comma)
            .finish(&mut df)
            .map_err(pe)
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

/// Data type codes. Keep in sync with `NqDtype` in nanuq/ffi.nim and
/// `DataTypeKind` in nanuq.nim (same order).
#[repr(C)]
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum NqDtype {
    Boolean = 0,
    Int8,
    Int16,
    Int32,
    Int64,
    UInt8,
    UInt16,
    UInt32,
    UInt64,
    Float32,
    Float64,
    String,
    Null,
    Other,
}

fn dtype_code(d: &DataType) -> NqDtype {
    match d {
        DataType::Boolean => NqDtype::Boolean,
        DataType::Int8 => NqDtype::Int8,
        DataType::Int16 => NqDtype::Int16,
        DataType::Int32 => NqDtype::Int32,
        DataType::Int64 => NqDtype::Int64,
        DataType::UInt8 => NqDtype::UInt8,
        DataType::UInt16 => NqDtype::UInt16,
        DataType::UInt32 => NqDtype::UInt32,
        DataType::UInt64 => NqDtype::UInt64,
        DataType::Float32 => NqDtype::Float32,
        DataType::Float64 => NqDtype::Float64,
        DataType::String => NqDtype::String,
        DataType::Null => NqDtype::Null,
        _ => NqDtype::Other,
    }
}

fn dtype_from_code(c: NqDtype) -> Result<DataType, String> {
    Ok(match c {
        NqDtype::Boolean => DataType::Boolean,
        NqDtype::Int8 => DataType::Int8,
        NqDtype::Int16 => DataType::Int16,
        NqDtype::Int32 => DataType::Int32,
        NqDtype::Int64 => DataType::Int64,
        NqDtype::UInt8 => DataType::UInt8,
        NqDtype::UInt16 => DataType::UInt16,
        NqDtype::UInt32 => DataType::UInt32,
        NqDtype::UInt64 => DataType::UInt64,
        NqDtype::Float32 => DataType::Float32,
        NqDtype::Float64 => DataType::Float64,
        NqDtype::String => DataType::String,
        NqDtype::Null => DataType::Null,
        NqDtype::Other => return Err("cannot cast to a dtype Nanuq does not model".into()),
    })
}

/// Data type code (`NqDtype`) of a column, or -1 on error.
#[no_mangle]
pub unsafe extern "C" fn nq_df_column_dtype_kind(df: *const DataFrame, name: *const c_char) -> i32 {
    guard(|| {
        let col = borrow(df, "DataFrame")?.column(cstr(name)?).map_err(pe)?;
        Ok(dtype_code(col.dtype()) as i32)
    })
    .unwrap_or(-1)
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

/// One cell as Python Polars' `get_fmt` shows it in HTML tables: the value's
/// Display form, with strings in quotes and cut after
/// `str_len` characters with an ellipsis.
#[no_mangle]
pub unsafe extern "C" fn nq_df_cell_fmt(
    df: *const DataFrame,
    name: *const c_char,
    row: usize,
    str_len: usize,
) -> *mut c_char {
    guard(|| {
        let df = borrow(df, "DataFrame")?;
        let name = cstr(name)?;
        let col = df.column(name).map_err(pe)?;
        let v = format!("{}", cell(df, name, row)?);
        let quoted = matches!(col.dtype(), DataType::String);
        if !quoted || v.len() < 2 {
            return Ok(to_c_string(v));
        }
        let inner = &v[1..v.len() - 1];
        let end = inner
            .char_indices()
            .take(str_len)
            .last()
            .map(|(i, c)| i + c.len_utf8())
            .unwrap_or(0);
        Ok(to_c_string(if end == inner.len() { v.clone() } else { format!("\"{}…", &inner[..end]) }))
    })
    .unwrap_or(ptr::null_mut())
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
    Mod,
    FloorDiv,
    Pow,
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
            NqBinOp::Div => a.true_div(b),
            NqBinOp::Eq => a.eq(b),
            NqBinOp::NotEq => a.neq(b),
            NqBinOp::Lt => a.lt(b),
            NqBinOp::LtEq => a.lt_eq(b),
            NqBinOp::Gt => a.gt(b),
            NqBinOp::GtEq => a.gt_eq(b),
            NqBinOp::And => a.and(b),
            NqBinOp::Or => a.or(b),
            NqBinOp::Mod => a % b,
            NqBinOp::FloorDiv => a.floor_div(b),
            NqBinOp::Pow => a.pow(b),
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
    Abs,
    Median,
    Len,
    Neg,
    NullCount,
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
            NqUnary::Abs => e.abs(),
            NqUnary::Median => e.median(),
            NqUnary::Len => e.len(),
            NqUnary::Neg => -e,
            NqUnary::NullCount => e.null_count(),
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

/// Casts to the dtype `code`; strict casts fail on values that can't be
/// converted, non-strict ones turn them into nulls.
#[no_mangle]
pub unsafe extern "C" fn nq_expr_cast(e: *const Expr, code: NqDtype, strict: bool) -> *mut Expr {
    boxed(guard(|| {
        let e = borrow(e, "expression")?.clone();
        let dt = dtype_from_code(code)?;
        Ok(if strict { e.strict_cast(dt) } else { e.cast(dt) })
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

/// Sorts by `n` key expressions. `descending` and `nulls_last` hold 0, 1 or
/// `n` values: none means false for every key, one applies to every key.
#[no_mangle]
pub unsafe extern "C" fn nq_lf_sort_by(
    lf_: *const LazyFrame,
    by: *const *const Expr,
    n: usize,
    descending: *const bool,
    n_desc: usize,
    nulls_last: *const bool,
    n_nulls: usize,
    maintain_order: bool,
) -> *mut LazyFrame {
    boxed(guard(|| {
        let by = exprs(by, n)?;
        if by.is_empty() {
            return Err("sort needs at least one key".into());
        }
        let flags = |p: *const bool, len: usize, what: &str| -> Result<Vec<bool>, String> {
            let v = slice(p, len)?.to_vec();
            match v.len() {
                0 => Ok(vec![false]),
                1 => Ok(v),
                l if l == by.len() => Ok(v),
                l => Err(format!("sort got {l} values for {what} but {} keys", by.len())),
            }
        };
        let opts = SortMultipleOptions::default()
            .with_order_descending_multi(flags(descending, n_desc, "descending")?)
            .with_nulls_last_multi(flags(nulls_last, n_nulls, "nullsLast")?)
            .with_maintain_order(maintain_order);
        Ok(lf(lf_)?.sort_by_exprs(by, opts))
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

/// The schema of the plan, without running it: an empty DataFrame with the
/// resolved column names and dtypes.
#[no_mangle]
pub unsafe extern "C" fn nq_lf_collect_schema(lf_: *const LazyFrame) -> *mut DataFrame {
    boxed(guard(|| {
        let schema = lf(lf_)?.collect_schema().map_err(pe)?;
        Ok(DataFrame::empty_with_arc_schema(schema))
    }))
}

/// Casts the `n` named columns to the matching dtype codes.
#[no_mangle]
pub unsafe extern "C" fn nq_lf_cast(
    lf_: *const LazyFrame,
    names: *const *const c_char,
    codes: *const NqDtype,
    n: usize,
    strict: bool,
) -> *mut LazyFrame {
    boxed(guard(|| {
        let names = slice(names, n)?;
        let codes = slice(codes, n)?;
        let mut map = PlHashMap::new();
        for (name, code) in names.iter().zip(codes) {
            map.insert(cstr(*name)?, dtype_from_code(*code)?);
        }
        Ok(lf(lf_)?.cast(map, strict))
    }))
}

/// Casts every column to the dtype `code`.
#[no_mangle]
pub unsafe extern "C" fn nq_lf_cast_all(lf_: *const LazyFrame, code: NqDtype, strict: bool) -> *mut LazyFrame {
    boxed(guard(|| Ok(lf(lf_)?.cast_all(dtype_from_code(code)?, strict))))
}

// ---------------------------------------------------------------------------
// Joins and concatenation
// ---------------------------------------------------------------------------

/// Join types. Keep in sync with `NqJoinType` in nanuq/ffi.nim and
/// `JoinType` in nanuq.nim (same order).
#[repr(C)]
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum NqJoinType {
    Inner = 0,
    Left,
    Right,
    Full,
    Semi,
    Anti,
    Cross,
}

/// Join key checks. Keep in sync with `NqJoinValidation` / `JoinValidation`.
#[repr(C)]
#[derive(Clone, Copy)]
pub enum NqJoinValidation {
    ManyToMany = 0,
    ManyToOne,
    OneToMany,
    OneToOne,
}

/// Row order of a join. Keep in sync with `NqMaintainOrderJoin` /
/// `MaintainOrderJoin`.
#[repr(C)]
#[derive(Clone, Copy)]
pub enum NqMaintainOrderJoin {
    None = 0,
    Left,
    Right,
    LeftRight,
    RightLeft,
}

/// Concatenation methods. Keep in sync with `NqConcat` / `ConcatMethod`.
#[repr(C)]
#[derive(Clone, Copy)]
pub enum NqConcat {
    Vertical = 0,
    VerticalRelaxed,
    Horizontal,
    Diagonal,
    DiagonalRelaxed,
}

/// Joins `left_` with `right_`. `coalesce` is -1 for Polars' per-join-type
/// default, 0 to keep both key columns, 1 to coalesce them. A cross join takes
/// no keys; every other join needs the same number of keys (at least one) on
/// each side.
#[no_mangle]
pub unsafe extern "C" fn nq_lf_join(
    left_: *const LazyFrame,
    right_: *const LazyFrame,
    left_on: *const *const Expr,
    n_left: usize,
    right_on: *const *const Expr,
    n_right: usize,
    how: NqJoinType,
    suffix: *const c_char,
    validate: NqJoinValidation,
    nulls_equal: bool,
    coalesce: i32,
    maintain_order: NqMaintainOrderJoin,
) -> *mut LazyFrame {
    boxed(guard(|| {
        let left_on = exprs(left_on, n_left)?;
        let right_on = exprs(right_on, n_right)?;
        if how == NqJoinType::Cross {
            if !left_on.is_empty() || !right_on.is_empty() {
                return Err("a cross join takes no join keys".into());
            }
        } else if left_on.is_empty() || left_on.len() != right_on.len() {
            return Err(format!(
                "a {how:?} join needs the same number of keys on both sides (got {} and {})",
                left_on.len(),
                right_on.len()
            ));
        }
        let mut args = JoinArgs::new(match how {
            NqJoinType::Inner => JoinType::Inner,
            NqJoinType::Left => JoinType::Left,
            NqJoinType::Right => JoinType::Right,
            NqJoinType::Full => JoinType::Full,
            NqJoinType::Semi => JoinType::Semi,
            NqJoinType::Anti => JoinType::Anti,
            NqJoinType::Cross => JoinType::Cross,
        });
        args.suffix = Some(cstr(suffix)?.into());
        args.validation = match validate {
            NqJoinValidation::ManyToMany => JoinValidation::ManyToMany,
            NqJoinValidation::ManyToOne => JoinValidation::ManyToOne,
            NqJoinValidation::OneToMany => JoinValidation::OneToMany,
            NqJoinValidation::OneToOne => JoinValidation::OneToOne,
        };
        args.nulls_equal = nulls_equal;
        args.coalesce = match coalesce {
            0 => JoinCoalesce::KeepColumns,
            1 => JoinCoalesce::CoalesceColumns,
            _ => JoinCoalesce::JoinSpecific,
        };
        args.maintain_order = match maintain_order {
            NqMaintainOrderJoin::None => MaintainOrderJoin::None,
            NqMaintainOrderJoin::Left => MaintainOrderJoin::Left,
            NqMaintainOrderJoin::Right => MaintainOrderJoin::Right,
            NqMaintainOrderJoin::LeftRight => MaintainOrderJoin::LeftRight,
            NqMaintainOrderJoin::RightLeft => MaintainOrderJoin::RightLeft,
        };
        Ok(lf(left_)?.join(lf(right_)?, left_on, right_on, args))
    }))
}

/// Concatenates `n` LazyFrames.
#[no_mangle]
pub unsafe extern "C" fn nq_lf_concat(
    lfs: *const *const LazyFrame,
    n: usize,
    how: NqConcat,
) -> *mut LazyFrame {
    boxed(guard(|| {
        let lfs = slice(lfs, n)?
            .iter()
            .map(|p| lf(*p))
            .collect::<Result<Vec<_>, _>>()?;
        if lfs.is_empty() {
            return Err("concat needs at least one frame".into());
        }
        let relaxed = matches!(how, NqConcat::VerticalRelaxed | NqConcat::DiagonalRelaxed);
        let args = UnionArgs { to_supertypes: relaxed, ..Default::default() };
        match how {
            NqConcat::Vertical | NqConcat::VerticalRelaxed => concat(lfs, args),
            NqConcat::Diagonal | NqConcat::DiagonalRelaxed => concat_lf_diagonal(lfs, args),
            NqConcat::Horizontal => concat_lf_horizontal(lfs, HConcatOptions::default()),
        }
        .map_err(pe)
    }))
}

// ---------------------------------------------------------------------------
// Frame verbs
// ---------------------------------------------------------------------------

unsafe fn names<'a>(p: *const *const c_char, n: usize) -> Result<Vec<&'a str>, String> {
    slice(p, n)?.iter().map(|s| cstr(*s)).collect()
}

/// Drops the `n` named columns; with `strict`, a missing one is an error.
#[no_mangle]
pub unsafe extern "C" fn nq_lf_drop(
    lf_: *const LazyFrame,
    cols_: *const *const c_char,
    n: usize,
    strict: bool,
) -> *mut LazyFrame {
    boxed(guard(|| Ok(lf(lf_)?.drop(by_name(names(cols_, n)?, strict, false)))))
}

/// Renames `existing[i]` to `new[i]` for the `n` pairs.
#[no_mangle]
pub unsafe extern "C" fn nq_lf_rename(
    lf_: *const LazyFrame,
    existing: *const *const c_char,
    new: *const *const c_char,
    n: usize,
    strict: bool,
) -> *mut LazyFrame {
    boxed(guard(|| Ok(lf(lf_)?.rename(names(existing, n)?, names(new, n)?, strict))))
}

/// `len` rows from `offset`; a negative offset counts from the end.
#[no_mangle]
pub unsafe extern "C" fn nq_lf_slice(lf_: *const LazyFrame, offset: i64, len: u32) -> *mut LazyFrame {
    boxed(guard(|| Ok(lf(lf_)?.slice(offset, len.into()))))
}

#[no_mangle]
pub unsafe extern "C" fn nq_lf_reverse(lf_: *const LazyFrame) -> *mut LazyFrame {
    boxed(guard(|| Ok(lf(lf_)?.reverse())))
}

#[no_mangle]
pub unsafe extern "C" fn nq_lf_with_row_index(
    lf_: *const LazyFrame,
    name: *const c_char,
    offset: u32,
) -> *mut LazyFrame {
    boxed(guard(|| Ok(lf(lf_)?.with_row_index(cstr(name)?, Some(offset.into())))))
}

/// Which row of a group of duplicates `unique` keeps. Same order as Nim's
/// `UniqueKeepStrategy`.
#[repr(C)]
#[derive(Clone, Copy)]
pub enum NqUniqueKeepStrategy {
    First,
    Last,
    None,
    Any,
}

/// Drops duplicate rows, judged on the `n` named columns (all when `n == 0`).
#[no_mangle]
pub unsafe extern "C" fn nq_lf_unique(
    lf_: *const LazyFrame,
    subset: *const *const c_char,
    n: usize,
    keep: NqUniqueKeepStrategy,
    maintain_order: bool,
) -> *mut LazyFrame {
    boxed(guard(|| {
        let subset = names(subset, n)?;
        let subset = (!subset.is_empty()).then(|| subset.into_iter().map(col).collect());
        let keep = match keep {
            NqUniqueKeepStrategy::First => UniqueKeepStrategy::First,
            NqUniqueKeepStrategy::Last => UniqueKeepStrategy::Last,
            NqUniqueKeepStrategy::None => UniqueKeepStrategy::None,
            NqUniqueKeepStrategy::Any => UniqueKeepStrategy::Any,
        };
        let lf = lf(lf_)?;
        Ok(if maintain_order {
            lf.unique_stable_generic(subset, keep)
        } else {
            lf.unique_generic(subset, keep)
        })
    }))
}

/// Random rows: `n` of them, or `fraction` of the height when `by_fraction`.
/// `seed` is used only when `has_seed`.
#[no_mangle]
pub unsafe extern "C" fn nq_df_sample(
    df: *const DataFrame,
    n: usize,
    fraction: f64,
    by_fraction: bool,
    with_replacement: bool,
    shuffle: bool,
    has_seed: bool,
    seed: u64,
) -> *mut DataFrame {
    boxed(guard(|| {
        let df = borrow(df, "DataFrame")?;
        let seed = has_seed.then_some(seed);
        if by_fraction {
            let frac = Series::new("frac".into(), [fraction]);
            df.sample_frac(&frac, with_replacement, Some(shuffle), seed).map_err(pe)
        } else {
            df.sample_n_literal(n, with_replacement, Some(shuffle), seed).map_err(pe)
        }
    }))
}

/// Seeds Polars' global random generator, used by random operations that get
/// no seed of their own.
#[no_mangle]
pub extern "C" fn nq_set_random_seed(seed: u64) {
    polars_core::random::set_global_random_seed(seed);
}

// ---------------------------------------------------------------------------
// More expressions
// ---------------------------------------------------------------------------

/// `when(conds[0]).then(values[0]).when(conds[1]).then(values[1])...`, ending
/// with `otherwise`, or null when `otherwise` is NULL.
#[no_mangle]
pub unsafe extern "C" fn nq_expr_when_then(
    conds: *const *const Expr,
    values: *const *const Expr,
    n: usize,
    otherwise: *const Expr,
) -> *mut Expr {
    boxed(guard(|| {
        let conds = exprs(conds, n)?;
        let values = exprs(values, n)?;
        if conds.is_empty() {
            return Err("when/then needs at least one branch".into());
        }
        let other = if otherwise.is_null() {
            lit(NULL)
        } else {
            borrow(otherwise, "expression")?.clone()
        };
        let mut it = conds.into_iter().zip(values);
        let (c0, v0) = it.next().unwrap();
        let first = when(c0).then(v0);
        let rest: Vec<(Expr, Expr)> = it.collect();
        if rest.is_empty() {
            return Ok(first.otherwise(other));
        }
        let mut chain = None::<ChainedThen>;
        let mut first = Some(first);
        for (c, v) in rest {
            chain = Some(match chain.take() {
                None => first.take().unwrap().when(c).then(v),
                Some(ch) => ch.when(c).then(v),
            });
        }
        Ok(chain.unwrap().otherwise(other))
    }))
}

/// A literal holding a whole Series (for `is_in` with a list of values).
#[no_mangle]
pub unsafe extern "C" fn nq_expr_lit_series(s: *const Series) -> *mut Expr {
    boxed(guard(|| Ok(lit(borrow(s, "Series")?.clone()).implode(true))))
}

#[no_mangle]
pub unsafe extern "C" fn nq_expr_is_in(
    e: *const Expr,
    other: *const Expr,
    nulls_equal: bool,
) -> *mut Expr {
    boxed(guard(|| {
        let e = borrow(e, "expression")?.clone();
        Ok(e.is_in(borrow(other, "expression")?.clone(), nulls_equal))
    }))
}

/// Same order as Nim's `ClosedInterval`.
#[repr(C)]
#[derive(Clone, Copy)]
pub enum NqClosedInterval {
    Both,
    Left,
    Right,
    None,
}

#[no_mangle]
pub unsafe extern "C" fn nq_expr_is_between(
    e: *const Expr,
    lower: *const Expr,
    upper: *const Expr,
    closed: NqClosedInterval,
) -> *mut Expr {
    boxed(guard(|| {
        let closed = match closed {
            NqClosedInterval::Both => ClosedInterval::Both,
            NqClosedInterval::Left => ClosedInterval::Left,
            NqClosedInterval::Right => ClosedInterval::Right,
            NqClosedInterval::None => ClosedInterval::None,
        };
        let e = borrow(e, "expression")?.clone();
        let lo = borrow(lower, "expression")?.clone();
        let hi = borrow(upper, "expression")?.clone();
        Ok(e.is_between(lo, hi, closed))
    }))
}

/// Same order as Nim's `QuantileMethod`.
#[repr(C)]
#[derive(Clone, Copy)]
pub enum NqQuantileMethod {
    Nearest,
    Lower,
    Higher,
    Midpoint,
    Linear,
    Equiprobable,
}

#[no_mangle]
pub unsafe extern "C" fn nq_expr_quantile(
    e: *const Expr,
    q: f64,
    method: NqQuantileMethod,
) -> *mut Expr {
    boxed(guard(|| {
        let method = match method {
            NqQuantileMethod::Nearest => QuantileMethod::Nearest,
            NqQuantileMethod::Lower => QuantileMethod::Lower,
            NqQuantileMethod::Higher => QuantileMethod::Higher,
            NqQuantileMethod::Midpoint => QuantileMethod::Midpoint,
            NqQuantileMethod::Linear => QuantileMethod::Linear,
            NqQuantileMethod::Equiprobable => QuantileMethod::Equiprobable,
        };
        Ok(borrow(e, "expression")?.clone().quantile(lit(q), method))
    }))
}

/// Variance (`is_var`) or standard deviation with `ddof` delta degrees of freedom.
#[no_mangle]
pub unsafe extern "C" fn nq_expr_var_std(e: *const Expr, ddof: u8, is_var: bool) -> *mut Expr {
    boxed(guard(|| {
        let e = borrow(e, "expression")?.clone();
        Ok(if is_var { e.var(ddof) } else { e.std(ddof) })
    }))
}

/// Same order as Nim's `FillNullStrategy`.
#[repr(C)]
#[derive(Clone, Copy)]
pub enum NqFillNullStrategy {
    Forward,
    Backward,
    Mean,
    Min,
    Max,
    Zero,
    One,
}

#[no_mangle]
pub unsafe extern "C" fn nq_expr_fill_null_strategy(
    e: *const Expr,
    strategy: NqFillNullStrategy,
    has_limit: bool,
    limit: u32,
) -> *mut Expr {
    boxed(guard(|| {
        let limit: Option<IdxSize> = has_limit.then_some(limit as IdxSize);
        let strategy = match strategy {
            NqFillNullStrategy::Forward => FillNullStrategy::Forward(limit),
            NqFillNullStrategy::Backward => FillNullStrategy::Backward(limit),
            NqFillNullStrategy::Mean => FillNullStrategy::Mean,
            NqFillNullStrategy::Min => FillNullStrategy::Min,
            NqFillNullStrategy::Max => FillNullStrategy::Max,
            NqFillNullStrategy::Zero => FillNullStrategy::Zero,
            NqFillNullStrategy::One => FillNullStrategy::One,
        };
        Ok(borrow(e, "expression")?.clone().fill_null_with_strategy(strategy))
    }))
}

/// Same order as Nim's `RoundMode`.
#[repr(C)]
#[derive(Clone, Copy)]
pub enum NqRoundMode {
    HalfToEven,
    HalfAwayFromZero,
    ToZero,
}

#[no_mangle]
pub unsafe extern "C" fn nq_expr_round(e: *const Expr, decimals: u32, mode: NqRoundMode) -> *mut Expr {
    boxed(guard(|| {
        let mode = match mode {
            NqRoundMode::HalfToEven => RoundMode::HalfToEven,
            NqRoundMode::HalfAwayFromZero => RoundMode::HalfAwayFromZero,
            NqRoundMode::ToZero => RoundMode::ToZero,
        };
        Ok(borrow(e, "expression")?.clone().round(decimals, mode))
    }))
}

/// Computes `e` per group of the `n` partition keys, one value per row.
#[no_mangle]
pub unsafe extern "C" fn nq_expr_over(
    e: *const Expr,
    by: *const *const Expr,
    n: usize,
) -> *mut Expr {
    boxed(guard(|| {
        let by = exprs(by, n)?;
        if by.is_empty() {
            return Err("over needs at least one partition key".into());
        }
        borrow(e, "expression")?.clone().over(by).map_err(pe)
    }))
}

// ---------------------------------------------------------------------------
// Column selectors
// ---------------------------------------------------------------------------

/// Dtype categories a selector can ask for, as bits of `classes` in
/// `nq_expr_selector`. Same order as Nim's `DtypeClass`.
#[repr(C)]
#[derive(Clone, Copy)]
pub enum NqDtypeClass {
    Numeric,
    Integer,
    SignedInteger,
    UnsignedInteger,
    Float,
}

/// The union of the named columns, the dtypes (codes), the dtype classes (bit
/// set of `NqDtypeClass`) and, with `wildcard`, every column, minus the
/// excluded names, as an expression.
#[no_mangle]
pub unsafe extern "C" fn nq_expr_selector(
    names_: *const *const c_char,
    n_names: usize,
    dtypes: *const NqDtype,
    n_dtypes: usize,
    classes: u32,
    wildcard: bool,
    excluded: *const *const c_char,
    n_excluded: usize,
) -> *mut Expr {
    boxed(guard(|| {
        let mut parts: Vec<Selector> = Vec::new();
        if wildcard {
            parts.push(Selector::Wildcard);
        }
        let ns = names(names_, n_names)?;
        if !ns.is_empty() {
            parts.push(by_name(ns, true, true));
        }
        let dts = slice(dtypes, n_dtypes)?
            .iter()
            .map(|c| dtype_from_code(*c))
            .collect::<Result<Vec<_>, _>>()?;
        if !dts.is_empty() {
            parts.push(Selector::ByDType(DataTypeSelector::AnyOf(dts.into())));
        }
        let all_classes = [
            (NqDtypeClass::Numeric, DataTypeSelector::Numeric),
            (NqDtypeClass::Integer, DataTypeSelector::Integer),
            (NqDtypeClass::SignedInteger, DataTypeSelector::SignedInteger),
            (NqDtypeClass::UnsignedInteger, DataTypeSelector::UnsignedInteger),
            (NqDtypeClass::Float, DataTypeSelector::Float),
        ];
        for (c, d) in all_classes {
            if classes & (1u32 << (c as u32)) != 0 {
                parts.push(Selector::ByDType(d));
            }
        }
        let mut it = parts.into_iter();
        let mut sel = it.next().ok_or("a selector needs names, types or all()")?;
        for p in it {
            sel = sel | p;
        }
        let ex = names(excluded, n_excluded)?;
        if !ex.is_empty() {
            sel = sel.exclude_cols(ex.into_iter().map(PlSmallStr::from).collect::<Vec<_>>());
        }
        Ok(sel.as_expr())
    }))
}

/// Appends (`prefix == false`) or prepends `affix` to every output name of `e`.
#[no_mangle]
pub unsafe extern "C" fn nq_expr_name_affix(
    e: *const Expr,
    affix: *const c_char,
    prefix: bool,
) -> *mut Expr {
    boxed(guard(|| {
        let e = borrow(e, "expression")?.clone();
        let a = cstr(affix)?;
        Ok(if prefix { e.name().prefix(a) } else { e.name().suffix(a) })
    }))
}

// ---------------------------------------------------------------------------
// Ranking
// ---------------------------------------------------------------------------

/// Rank methods. Keep in sync with `NqRankMethod` in nanuq/ffi.nim and
/// `RankMethod` in nanuq.nim.
#[repr(C)]
#[derive(Clone, Copy)]
pub enum NqRankMethod {
    Average = 0,
    Min,
    Max,
    Dense,
    Ordinal,
    Random,
}

#[no_mangle]
pub unsafe extern "C" fn nq_expr_rank(
    e: *const Expr,
    method: NqRankMethod,
    descending: bool,
    has_seed: bool,
    seed: u64,
) -> *mut Expr {
    boxed(guard(|| {
        let method = match method {
            NqRankMethod::Average => RankMethod::Average,
            NqRankMethod::Min => RankMethod::Min,
            NqRankMethod::Max => RankMethod::Max,
            NqRankMethod::Dense => RankMethod::Dense,
            NqRankMethod::Ordinal => RankMethod::Ordinal,
            NqRankMethod::Random => RankMethod::Random,
        };
        let opts = RankOptions { method, descending };
        Ok(borrow(e, "expression")?
            .clone()
            .rank(opts, if has_seed { Some(seed) } else { None }))
    }))
}
