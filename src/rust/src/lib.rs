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


#[cfg(feature = "jemalloc")]
#[global_allocator]
static GLOBAL: tikv_jemallocator::Jemalloc = tikv_jemallocator::Jemalloc;

use std::cell::{Cell, RefCell};
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
    static LAST_KIND: Cell<NqErrorKind> = const { Cell::new(NqErrorKind::Generic) };
}

/// Kind of the last error. Keep in sync with `NqErrorKind` in nanuq/ffi.nim.
#[repr(C)]
#[derive(Clone, Copy)]
pub enum NqErrorKind {
    Generic = 0,
    ColumnNotFound,
    Compute,
    Duplicate,
    InvalidOperation,
    Io,
    NoData,
    OutOfBounds,
    Schema,
    SchemaFieldNotFound,
    Shape,
    StructFieldNotFound,
    Sql,
}

fn error_kind(e: &PolarsError) -> NqErrorKind {
    match e {
        PolarsError::ColumnNotFound(_) => NqErrorKind::ColumnNotFound,
        PolarsError::ComputeError(_) => NqErrorKind::Compute,
        PolarsError::Duplicate(_) => NqErrorKind::Duplicate,
        PolarsError::InvalidOperation(_) => NqErrorKind::InvalidOperation,
        PolarsError::IO { .. } => NqErrorKind::Io,
        PolarsError::NoData(_) => NqErrorKind::NoData,
        PolarsError::OutOfBounds(_) => NqErrorKind::OutOfBounds,
        PolarsError::SchemaMismatch(_) => NqErrorKind::Schema,
        PolarsError::SchemaFieldNotFound(_) => NqErrorKind::SchemaFieldNotFound,
        PolarsError::ShapeMismatch(_) => NqErrorKind::Shape,
        PolarsError::StructFieldNotFound(_) => NqErrorKind::StructFieldNotFound,
        PolarsError::SQLInterface(_) | PolarsError::SQLSyntax(_) => NqErrorKind::Sql,
        PolarsError::Context { error, .. } | PolarsError::ExprContext { error, .. } => {
            error_kind(error)
        }
        _ => NqErrorKind::Generic,
    }
}

fn set_error(msg: impl Into<String>) {
    let msg = msg.into().replace('\0', " ");
    LAST_ERROR.with(|e| *e.borrow_mut() = CString::new(msg).ok());
}

fn clear_error() {
    LAST_ERROR.with(|e| *e.borrow_mut() = None);
    LAST_KIND.with(|k| k.set(NqErrorKind::Generic));
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
            LAST_KIND.with(|k| k.set(NqErrorKind::Generic));
            set_error(format!("panic in polars: {msg}"));
            None
        }
    }
}

fn boxed<T>(v: Option<T>) -> *mut T {
    v.map_or(ptr::null_mut(), |v| Box::into_raw(Box::new(v)))
}

/// Converts a Polars error to its message, recording its kind for
/// `nq_last_error_kind`.
fn pe(e: PolarsError) -> String {
    let kind = error_kind(&e);
    LAST_KIND.with(|k| k.set(kind));
    e.to_string()
}

/// Converts an IO error to its message, recording the `Io` kind.
fn ioe(e: std::io::Error) -> String {
    LAST_KIND.with(|k| k.set(NqErrorKind::Io));
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

/// Kind of the last error on this thread (`Generic` for panics and Nanuq's own
/// errors). Only meaningful right after a call failed.
#[no_mangle]
pub extern "C" fn nq_last_error_kind() -> NqErrorKind {
    LAST_KIND.with(|k| k.get())
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
/// from all rows. When `data` is not NULL, its `data_len` bytes are read instead
/// of `path`.
#[no_mangle]
pub unsafe extern "C" fn nq_lf_scan_csv(
    path: *const c_char,
    data: *const u8,
    data_len: usize,
    separator: u8,
    has_header: bool,
    null_values: *const *const c_char,
    n_nulls: usize,
    override_names: *const *const c_char,
    override_dtypes: *const NqDtypeSpec,
    n_overrides: usize,
    skip_rows: usize,
    n_rows: i64,
    infer_schema_length: i64,
    ignore_errors: bool,
    decimal_comma: bool,
    try_parse_dates: bool,
) -> *mut LazyFrame {
    boxed(guard(|| {
        let sources = scan_sources(path, data, data_len)?;
        let nulls = names(null_values, n_nulls)?
            .into_iter()
            .map(PlSmallStr::from)
            .collect::<Vec<_>>();
        let nulls = (!nulls.is_empty()).then(|| NullValues::AllColumns(nulls));
        let onames = names(override_names, n_overrides)?;
        let odtypes = dtypes_from_specs(override_dtypes, n_overrides)?;
        let overrides = if n_overrides == 0 {
            None
        } else {
            let fields = onames
                .iter()
                .zip(odtypes)
                .map(|(n, d)| Ok(Field::new((*n).into(), d.clone())))
                .collect::<Result<Vec<_>, String>>()?;
            Some(Arc::new(Schema::from_iter(fields)))
        };
        let opt = |v: i64| (v >= 0).then_some(v as usize);
        LazyCsvReader::new_with_sources(sources)
            .with_separator(separator)
            .with_has_header(has_header)
            .with_null_values(nulls)
            .with_dtype_overwrite(overrides)
            .with_skip_rows(skip_rows)
            .with_n_rows(opt(n_rows))
            .with_infer_schema_length(opt(infer_schema_length))
            .with_ignore_errors(ignore_errors)
            .with_decimal_comma(decimal_comma)
            .with_try_parse_dates(try_parse_dates)
            .finish()
            .map_err(pe)
    }))
}

use polars::polars_utils::compression::{BrotliLevel, GzipLevel, ZstdLevel};
use polars::polars_utils::slice_enum::Slice;

/// The sources of a scan: the file or glob `path`, or `data_len` bytes at `data`
/// when `data` is not NULL (the bytes are copied).
unsafe fn scan_sources(
    path: *const c_char,
    data: *const u8,
    data_len: usize,
) -> Result<ScanSources, String> {
    if data.is_null() {
        let path = cstr(path)?;
        Ok(ScanSources::Paths(std::iter::once(PlRefPath::from(path)).collect()))
    } else {
        let bytes = std::slice::from_raw_parts(data, data_len).to_vec();
        Ok(ScanSources::Buffers(Arc::from(vec![bytes.into()])))
    }
}

/// Hive partitioning detected automatically, as Python's `hive_partitioning =
/// None`, except for in-memory bytes, where Polars does not implement it.
fn no_hive_for_buffers(sources: &ScanSources) -> HiveOptions {
    if matches!(sources, ScanSources::Buffers(_)) {
        HiveOptions::new_disabled()
    } else {
        HiveOptions { enabled: None, ..HiveOptions::new_enabled() }
    }
}

unsafe fn row_index(name: *const c_char, offset: u32) -> Result<Option<RowIndex>, String> {
    if name.is_null() {
        return Ok(None);
    }
    Ok(Some(RowIndex { name: cstr(name)?.into(), offset: offset as IdxSize }))
}

/// Lazily scans a Parquet file or glob, or `data_len` bytes at `data`. `n_rows < 0`
/// reads all rows; a NULL `row_index_name` adds no row index.
#[no_mangle]
pub unsafe extern "C" fn nq_lf_scan_parquet(
    path: *const c_char,
    data: *const u8,
    data_len: usize,
    n_rows: i64,
    row_index_name: *const c_char,
    row_index_offset: u32,
    low_memory: bool,
) -> *mut LazyFrame {
    boxed(guard(|| {
        let sources = scan_sources(path, data, data_len)?;
        let hive_options = no_hive_for_buffers(&sources);
        let args = ScanArgsParquet {
            hive_options,
            n_rows: (n_rows >= 0).then_some(n_rows as usize),
            row_index: row_index(row_index_name, row_index_offset)?,
            low_memory,
            ..Default::default()
        };
        LazyFrame::scan_parquet_sources(sources, args).map_err(pe)
    }))
}

/// Lazily scans an Arrow IPC (Feather v2) file or glob, or `data_len` bytes at
/// `data`. Same conventions as `nq_lf_scan_parquet`.
#[no_mangle]
pub unsafe extern "C" fn nq_lf_scan_ipc(
    path: *const c_char,
    data: *const u8,
    data_len: usize,
    n_rows: i64,
    row_index_name: *const c_char,
    row_index_offset: u32,
) -> *mut LazyFrame {
    boxed(guard(|| {
        let sources = scan_sources(path, data, data_len)?;
        let hive_options = no_hive_for_buffers(&sources);
        let args = UnifiedScanArgs {
            hive_options,
            pre_slice: (n_rows >= 0).then(|| Slice::Positive { offset: 0, len: n_rows as usize }),
            row_index: row_index(row_index_name, row_index_offset)?,
            ..Default::default()
        };
        LazyFrame::scan_ipc_sources(sources, Default::default(), args).map_err(pe)
    }))
}

/// Parquet compressions for `nq_df_write_parquet`. Same order as Nim's
/// `ParquetCompression`.
#[repr(C)]
#[derive(Clone, Copy)]
pub enum NqParquetCompression {
    Lz4 = 0,
    Uncompressed,
    Snappy,
    Gzip,
    Brotli,
    Zstd,
}

/// Writes a Parquet file. `level < 0` uses the codec's default level;
/// `row_group_size <= 0` uses Polars' default.
#[no_mangle]
pub unsafe extern "C" fn nq_df_write_parquet(
    df: *const DataFrame,
    path: *const c_char,
    compression: NqParquetCompression,
    level: i32,
    statistics: bool,
    row_group_size: i64,
) -> bool {
    guard(|| {
        let mut df = borrow(df, "DataFrame")?.clone();
        let lvl = (level >= 0).then_some(level);
        let compression = match compression {
            NqParquetCompression::Lz4 => ParquetCompression::Lz4Raw,
            NqParquetCompression::Uncompressed => ParquetCompression::Uncompressed,
            NqParquetCompression::Snappy => ParquetCompression::Snappy,
            NqParquetCompression::Gzip => ParquetCompression::Gzip(
                lvl.map(|l| GzipLevel::try_new(l as u8)).transpose().map_err(|e| pe(e.into()))?,
            ),
            NqParquetCompression::Brotli => ParquetCompression::Brotli(
                lvl.map(|l| BrotliLevel::try_new(l as u32)).transpose().map_err(|e| pe(e.into()))?,
            ),
            NqParquetCompression::Zstd => ParquetCompression::Zstd(
                lvl.map(ZstdLevel::try_new).transpose().map_err(|e| pe(e.into()))?,
            ),
        };
        let stats = if statistics {
            StatisticsOptions::default()
        } else {
            StatisticsOptions::empty()
        };
        let file = File::create(cstr(path)?).map_err(ioe)?;
        ParquetWriter::new(file)
            .with_compression(compression)
            .with_statistics(stats)
            .with_row_group_size((row_group_size > 0).then_some(row_group_size as usize))
            .finish(&mut df)
            .map_err(pe)?;
        Ok(())
    })
    .is_some()
}

/// IPC compressions for `nq_df_write_ipc`. Same order as Nim's `IpcCompression`.
#[repr(C)]
#[derive(Clone, Copy)]
pub enum NqIpcCompression {
    Uncompressed = 0,
    Lz4,
    Zstd,
}

/// Writes an Arrow IPC (Feather v2) file.
#[no_mangle]
pub unsafe extern "C" fn nq_df_write_ipc(
    df: *const DataFrame,
    path: *const c_char,
    compression: NqIpcCompression,
) -> bool {
    guard(|| {
        let mut df = borrow(df, "DataFrame")?.clone();
        let compression = match compression {
            NqIpcCompression::Uncompressed => None,
            NqIpcCompression::Lz4 => Some(IpcCompression::LZ4),
            NqIpcCompression::Zstd => Some(IpcCompression::ZSTD(Default::default())),
        };
        let file = File::create(cstr(path)?).map_err(ioe)?;
        IpcWriter::new(file)
            .with_compression(compression)
            .finish(&mut df)
            .map_err(pe)
    })
    .is_some()
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
        let mut file = File::create(cstr(path)?).map_err(ioe)?;
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
    Date,
    Datetime,
    Duration,
    Time,
    Categorical,
    Enum,
    List,
    Array,
    Struct,
    Other,
}

/// Time units. Keep in sync with `NqTimeUnit` in nanuq/ffi.nim and `TimeUnit`
/// in nanuq.nim.
#[repr(C)]
#[derive(Clone, Copy)]
pub enum NqTimeUnit {
    Nanoseconds = 0,
    Microseconds,
    Milliseconds,
}

fn time_unit(u: NqTimeUnit) -> TimeUnit {
    match u {
        NqTimeUnit::Nanoseconds => TimeUnit::Nanoseconds,
        NqTimeUnit::Microseconds => TimeUnit::Microseconds,
        NqTimeUnit::Milliseconds => TimeUnit::Milliseconds,
    }
}

fn time_unit_code(u: &TimeUnit) -> NqTimeUnit {
    match u {
        TimeUnit::Nanoseconds => NqTimeUnit::Nanoseconds,
        TimeUnit::Microseconds => NqTimeUnit::Microseconds,
        TimeUnit::Milliseconds => NqTimeUnit::Milliseconds,
    }
}

/// A data type with its parameters, as Nim passes it: `time_unit` and
/// `time_zone` (NULL or "" for none) apply to Datetime and Duration;
/// `categories` (n_categories) to Enum.
#[repr(C)]
pub struct NqDtypeSpec {
    pub code: NqDtype,
    pub time_unit: NqTimeUnit,
    pub time_zone: *const c_char,
    pub categories: *const *const c_char,
    pub n_categories: usize,
    /// For List, Array and Struct: the whole type, as a handle (`nq_dtype_*`).
    pub nested: *const DataType,
}

unsafe fn time_zone(tz: *const c_char) -> Result<Option<TimeZone>, String> {
    if tz.is_null() {
        return Ok(None);
    }
    let tz = cstr(tz)?;
    if tz.is_empty() {
        return Ok(None);
    }
    TimeZone::opt_try_new(Some(tz)).map_err(pe)
}

unsafe fn dtype_from_spec(spec: &NqDtypeSpec) -> Result<DataType, String> {
    Ok(match spec.code {
        NqDtype::Date => DataType::Date,
        NqDtype::Datetime => DataType::Datetime(time_unit(spec.time_unit), time_zone(spec.time_zone)?),
        NqDtype::Duration => DataType::Duration(time_unit(spec.time_unit)),
        NqDtype::Time => DataType::Time,
        NqDtype::Categorical => DataType::from_categories(Categories::global()),
        NqDtype::Enum => {
            let cats = names(spec.categories, spec.n_categories)?;
            DataType::from_frozen_categories(FrozenCategories::new(cats).map_err(pe)?)
        }
        NqDtype::List | NqDtype::Array | NqDtype::Struct => borrow(spec.nested, "nested dtype")?.clone(),
        c => dtype_from_code(c)?,
    })
}

unsafe fn dtypes_from_specs(p: *const NqDtypeSpec, n: usize) -> Result<Vec<DataType>, String> {
    slice(p, n)?.iter().map(|s| dtype_from_spec(s)).collect()
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
        DataType::Date => NqDtype::Date,
        DataType::Datetime(_, _) => NqDtype::Datetime,
        DataType::Duration(_) => NqDtype::Duration,
        DataType::Time => NqDtype::Time,
        DataType::Categorical(_, _) => NqDtype::Categorical,
        DataType::Enum(_, _) => NqDtype::Enum,
        DataType::List(_) => NqDtype::List,
        DataType::Array(_, _) => NqDtype::Array,
        DataType::Struct(_) => NqDtype::Struct,
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
        NqDtype::Date
        | NqDtype::Datetime
        | NqDtype::Duration
        | NqDtype::Time
        | NqDtype::Categorical
        | NqDtype::Enum
        | NqDtype::List
        | NqDtype::Array
        | NqDtype::Struct => return Err("this dtype needs its parameters".into()),
        NqDtype::Other => return Err("cannot cast to a dtype Nanuq does not model".into()),
    })
}

/// A copy of `s` cast to `dtype` (strict: values that do not fit raise).
#[no_mangle]
pub unsafe extern "C" fn nq_series_cast(s: *const Series, dtype: *const NqDtypeSpec) -> *mut Series {
    boxed(guard(|| {
        let dt = dtype_from_spec(borrow(dtype, "dtype")?)?;
        borrow(s, "series")?.strict_cast(&dt).map_err(pe)
    }))
}

/// Number of categories of an Enum column, or -1 on error.
#[no_mangle]
pub unsafe extern "C" fn nq_df_column_n_categories(df: *const DataFrame, name: *const c_char) -> i64 {
    guard(|| match borrow(df, "DataFrame")?.column(cstr(name)?).map_err(pe)?.dtype() {
        DataType::Enum(fcats, _) => Ok(fcats.categories().len() as i64),
        dt => Err(format!("{dt} has no fixed categories")),
    })
    .unwrap_or(-1)
}

/// Category `i` of an Enum column, or NULL on error. Free with `nq_string_free`.
#[no_mangle]
pub unsafe extern "C" fn nq_df_column_category(
    df: *const DataFrame,
    name: *const c_char,
    i: usize,
) -> *mut c_char {
    guard(|| match borrow(df, "DataFrame")?.column(cstr(name)?).map_err(pe)?.dtype() {
        DataType::Enum(fcats, _) => {
            let cats = fcats.categories();
            if i >= cats.len() {
                return Err(format!("category {i} out of range"));
            }
            Ok(to_c_string(cats.value(i).to_string()))
        }
        dt => Err(format!("{dt} has no fixed categories")),
    })
    .unwrap_or(ptr::null_mut())
}

/// Functions of the `cat` namespace. Same order as `NqCatOp` in ffi.nim.
#[repr(C)]
#[derive(Clone, Copy)]
pub enum NqCatOp {
    GetCategories = 0,
    LenBytes,
    LenChars,
    StartsWith,
    EndsWith,
    Slice,
}

/// A `cat` namespace function. `s` is the prefix or suffix; `offset` and
/// `length` (`< 0`: to the end) are for `Slice`.
#[no_mangle]
pub unsafe extern "C" fn nq_expr_cat(
    e: *const Expr,
    op: NqCatOp,
    s: *const c_char,
    offset: i64,
    length: i64,
) -> *mut Expr {
    boxed(guard(|| {
        let e = borrow(e, "expr")?.clone().cat();
        Ok(match op {
            NqCatOp::GetCategories => e.get_categories(),
            NqCatOp::LenBytes => e.len_bytes(),
            NqCatOp::LenChars => e.len_chars(),
            NqCatOp::StartsWith => e.starts_with(cstr(s)?.to_string()),
            NqCatOp::EndsWith => e.ends_with(cstr(s)?.to_string()),
            NqCatOp::Slice => e.slice(offset, (length >= 0).then_some(length as usize)),
        })
    }))
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
    if matches!(col.dtype(), DataType::Duration(_)) && to == DataType::String {
        // Polars can't cast durations to strings: format them as it prints them
        let one = DataFrame::new(len, vec![col.clone()]).map_err(pe)?;
        let out = one
            .lazy()
            .select([polars::lazy::dsl::col(name).dt().to_string("polars")])
            .collect()
            .map_err(pe)?;
        return Ok(out.columns()[0].as_materialized_series().clone());
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
    // 0.4: elementwise math (add-expr-math)
    Sqrt,
    Cbrt,
    Exp,
    Log10,
    Log1p,
    Sign,
    Floor,
    Ceil,
    Sin,
    Cos,
    Tan,
    Cot,
    ArcSin,
    ArcCos,
    ArcTan,
    Sinh,
    Cosh,
    Tanh,
    ArcSinh,
    ArcCosh,
    ArcTanh,
    Degrees,
    Radians,
    IsNan,
    IsNotNan,
    IsFinite,
    IsInfinite,
    DropNans,
    DropNulls,
    // 0.4: add-cumulative-and-shift
    Product,
    Mode,
    ArgMin,
    ArgMax,
    RleId,
    PeakMax,
    PeakMin,
    // 0.4: add-value-functions
    Unique,
    UniqueStable,
    ArgUnique,
    IsUnique,
    IsDuplicated,
    IsFirstDistinct,
    IsLastDistinct,
    UniqueCounts,
    ApproxNUnique,
    Reverse,
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
            NqUnary::Sqrt => e.sqrt(),
            NqUnary::Cbrt => e.cbrt(),
            NqUnary::Exp => e.exp(),
            NqUnary::Log10 => e.log(lit(10.0)),
            NqUnary::Log1p => e.log1p(),
            NqUnary::Sign => e.sign(),
            NqUnary::Floor => e.floor(),
            NqUnary::Ceil => e.ceil(),
            NqUnary::Sin => e.sin(),
            NqUnary::Cos => e.cos(),
            NqUnary::Tan => e.tan(),
            NqUnary::Cot => e.cot(),
            NqUnary::ArcSin => e.arcsin(),
            NqUnary::ArcCos => e.arccos(),
            NqUnary::ArcTan => e.arctan(),
            NqUnary::Sinh => e.sinh(),
            NqUnary::Cosh => e.cosh(),
            NqUnary::Tanh => e.tanh(),
            NqUnary::ArcSinh => e.arcsinh(),
            NqUnary::ArcCosh => e.arccosh(),
            NqUnary::ArcTanh => e.arctanh(),
            NqUnary::Degrees => e.degrees(),
            NqUnary::Radians => e.radians(),
            NqUnary::IsNan => e.is_nan(),
            NqUnary::IsNotNan => e.is_not_nan(),
            NqUnary::IsFinite => e.is_finite(),
            NqUnary::IsInfinite => e.is_infinite(),
            NqUnary::DropNans => e.drop_nans(),
            NqUnary::DropNulls => e.drop_nulls(),
            NqUnary::Product => e.product(),
            NqUnary::Mode => e.mode(true),
            NqUnary::ArgMin => e.arg_min(),
            NqUnary::ArgMax => e.arg_max(),
            NqUnary::RleId => e.rle_id(),
            NqUnary::PeakMax => e.peak_max(),
            NqUnary::PeakMin => e.peak_min(),
            NqUnary::Unique => e.unique(),
            NqUnary::UniqueStable => e.unique_stable(),
            NqUnary::ArgUnique => e.arg_unique(),
            NqUnary::IsUnique => e.is_unique(),
            NqUnary::IsDuplicated => e.is_duplicated(),
            NqUnary::IsFirstDistinct => e.is_first_distinct(),
            NqUnary::IsLastDistinct => e.is_last_distinct(),
            NqUnary::UniqueCounts => e.unique_counts(),
            NqUnary::ApproxNUnique => e.approx_n_unique(),
            NqUnary::Reverse => e.reverse(),
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
pub unsafe extern "C" fn nq_expr_cast(e: *const Expr, spec: *const NqDtypeSpec, strict: bool) -> *mut Expr {
    boxed(guard(|| {
        let e = borrow(e, "expression")?.clone();
        let dt = dtype_from_spec(borrow(spec, "dtype")?)?;
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
    specs: *const NqDtypeSpec,
    n: usize,
    strict: bool,
) -> *mut LazyFrame {
    boxed(guard(|| {
        let names = slice(names, n)?;
        let dts = dtypes_from_specs(specs, n)?;
        let mut map = PlHashMap::new();
        for (name, dt) in names.iter().zip(dts) {
            map.insert(cstr(*name)?, dt);
        }
        Ok(lf(lf_)?.cast(map, strict))
    }))
}

/// Casts every column to the dtype `code`.
#[no_mangle]
pub unsafe extern "C" fn nq_lf_cast_all(lf_: *const LazyFrame, spec: *const NqDtypeSpec, strict: bool) -> *mut LazyFrame {
    boxed(guard(|| Ok(lf(lf_)?.cast_all(dtype_from_spec(borrow(spec, "dtype")?)?, strict))))
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

/// Keeps the values of `e` where `predicate` is true (Polars' `Expr.filter`).
#[no_mangle]
pub unsafe extern "C" fn nq_expr_filter(e: *const Expr, predicate: *const Expr) -> *mut Expr {
    boxed(guard(|| {
        let p = borrow(predicate, "predicate")?.clone();
        Ok(borrow(e, "expression")?.clone().filter(p))
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
    dtypes: *const NqDtypeSpec,
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
        let dts = dtypes_from_specs(dtypes, n_dtypes)?;
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

// ---------------------------------------------------------------------------
// String namespace
// ---------------------------------------------------------------------------

/// String functions. Keep in sync with `NqStrOp` in nanuq/ffi.nim.
#[repr(C)]
#[derive(Clone, Copy)]
pub enum NqStrOp {
    LenChars = 0,
    LenBytes,
    ToUppercase,
    ToLowercase,
    StripChars,
    StripCharsStart,
    StripCharsEnd,
    StripPrefix,
    StripSuffix,
    StartsWith,
    EndsWith,
    Contains,
    Find,
    CountMatches,
    Extract,
    Replace,
    ReplaceAll,
    Slice,
    Head,
    Tail,
    PadStart,
    PadEnd,
    Zfill,
    Reverse,
    Join,
    ToTitlecase,
}

/// `str.to_titlecase`, which Polars only has with its nightly feature.
#[cfg(feature = "nightly")]
fn titlecase(ns: polars::lazy::dsl::string::StringNameSpace) -> Result<Expr, String> {
    Ok(ns.to_titlecase())
}

#[cfg(not(feature = "nightly"))]
fn titlecase(_ns: polars::lazy::dsl::string::StringNameSpace) -> Result<Expr, String> {
    LAST_KIND.with(|k| k.set(NqErrorKind::InvalidOperation));
    Err("str.toTitlecase needs the native library built with the nightly feature \
         (the prebuilt release libraries are)"
        .into())
}

fn opt_expr(p: *const Expr) -> Result<Expr, String> {
    Ok(match unsafe { p.as_ref() } {
        Some(e) => e.clone(),
        None => Null {}.lit(),
    })
}

/// One entry point for the `str` namespace. `a` and `b` are the expression
/// arguments (NULL: a null literal), `flag1`/`flag2` the boolean options
/// (`literal`/`strict`, `ignore_nulls`), `n` a count or group index, `ch` a
/// fill character and `s` a string option (the `join` delimiter).
#[no_mangle]
pub unsafe extern "C" fn nq_expr_str(
    e: *const Expr,
    op: NqStrOp,
    a: *const Expr,
    b: *const Expr,
    flag1: bool,
    flag2: bool,
    n: i64,
    ch: u32,
    s: *const c_char,
) -> *mut Expr {
    boxed(guard(|| {
        let ns = borrow(e, "expression")?.clone().str();
        let a = opt_expr(a)?;
        let b = opt_expr(b)?;
        let fill = || char::from_u32(ch).ok_or_else(|| "invalid fill character".to_string());
        Ok(match op {
            NqStrOp::LenChars => ns.len_chars(),
            NqStrOp::LenBytes => ns.len_bytes(),
            NqStrOp::ToUppercase => ns.to_uppercase(),
            NqStrOp::ToLowercase => ns.to_lowercase(),
            NqStrOp::StripChars => ns.strip_chars(a),
            NqStrOp::StripCharsStart => ns.strip_chars_start(a),
            NqStrOp::StripCharsEnd => ns.strip_chars_end(a),
            NqStrOp::StripPrefix => ns.strip_prefix(a),
            NqStrOp::StripSuffix => ns.strip_suffix(a),
            NqStrOp::StartsWith => ns.starts_with(a),
            NqStrOp::EndsWith => ns.ends_with(a),
            NqStrOp::Contains => {
                if flag1 { ns.contains_literal(a) } else { ns.contains(a, flag2) }
            }
            NqStrOp::Find => {
                if flag1 { ns.find_literal(a) } else { ns.find(a, flag2) }
            }
            NqStrOp::CountMatches => ns.count_matches(a, flag1),
            NqStrOp::Extract => {
                ns.extract(a, usize::try_from(n).map_err(|_| "negative group index")?)
            }
            NqStrOp::Replace => ns.replace_n(a, b, flag1, n),
            NqStrOp::ReplaceAll => ns.replace_all(a, b, flag1),
            NqStrOp::Slice => ns.slice(a, b),
            NqStrOp::Head => ns.head(a),
            NqStrOp::Tail => ns.tail(a),
            NqStrOp::PadStart => ns.pad_start(a, fill()?),
            NqStrOp::PadEnd => ns.pad_end(a, fill()?),
            NqStrOp::Zfill => ns.zfill(a),
            NqStrOp::Reverse => ns.reverse(),
            NqStrOp::Join => ns.join(cstr(s)?, flag1),
            NqStrOp::ToTitlecase => titlecase(ns)?,
        })
    }))
}

/// Horizontal string concatenation (`concat_str`).
#[no_mangle]
pub unsafe extern "C" fn nq_expr_concat_str(
    es: *const *const Expr,
    len: usize,
    separator: *const c_char,
    ignore_nulls: bool,
) -> *mut Expr {
    boxed(guard(|| Ok(concat_str(exprs(es, len)?, cstr(separator)?, ignore_nulls))))
}

// ---------------------------------------------------------------------------
// Temporal values
// ---------------------------------------------------------------------------

/// Time unit of a Datetime or Duration column, or -1 (with an error) for other
/// columns.
#[no_mangle]
pub unsafe extern "C" fn nq_df_column_time_unit(df: *const DataFrame, name: *const c_char) -> i32 {
    guard(|| {
        let df = borrow(df, "dataframe")?;
        match df.column(cstr(name)?).map_err(pe)?.dtype() {
            DataType::Datetime(tu, _) | DataType::Duration(tu) => Ok(time_unit_code(tu) as i32),
            dt => Err(format!("{dt} has no time unit")),
        }
    })
    .unwrap_or(-1)
}

/// Time zone of a Datetime column ("" when it has none). Free with nq_string_free.
#[no_mangle]
pub unsafe extern "C" fn nq_df_column_time_zone(df: *const DataFrame, name: *const c_char) -> *mut c_char {
    guard(|| {
        let df = borrow(df, "dataframe")?;
        match df.column(cstr(name)?).map_err(pe)?.dtype() {
            DataType::Datetime(_, tz) => {
                Ok(to_c_string(tz.as_ref().map_or(String::new(), |z| z.to_string())))
            }
            dt => Err(format!("{dt} has no time zone")),
        }
    })
    .unwrap_or(ptr::null_mut())
}

/// The physical values of a column (days for Date, the time unit for Datetime
/// and Duration, nanoseconds for Time) as i64, with validity, into
/// caller-provided buffers of length `n` (the column's length).
#[no_mangle]
pub unsafe extern "C" fn nq_df_column_physical(
    df: *const DataFrame,
    name: *const c_char,
    out: *mut i64,
    valid: *mut bool,
    n: usize,
) -> bool {
    guard(|| {
        let df = borrow(df, "dataframe")?;
        let s = df.column(cstr(name)?).map_err(pe)?.as_materialized_series();
        if s.len() != n {
            return Err(format!("expected {} rows, got {n}", s.len()));
        }
        let phys = s.to_physical_repr().cast(&DataType::Int64).map_err(pe)?;
        let ca = phys.i64().map_err(pe)?;
        let out = std::slice::from_raw_parts_mut(out, n);
        let valid = std::slice::from_raw_parts_mut(valid, n);
        for (i, v) in ca.iter().enumerate() {
            out[i] = v.unwrap_or(0);
            valid[i] = v.is_some();
        }
        Ok(())
    })
    .is_some()
}

unsafe fn physical_series(
    name: &str,
    values: &[i64],
    valid: Option<&[bool]>,
    spec: &NqDtypeSpec,
) -> Result<Series, String> {
    let ca: Int64Chunked = match valid {
        Some(v) => values
            .iter()
            .zip(v)
            .map(|(x, ok)| ok.then_some(*x))
            .collect(),
        None => values.iter().copied().map(Some).collect(),
    };
    let s = ca.with_name(name.into()).into_series();
    Ok(match spec.code {
        NqDtype::Date => s.cast(&DataType::Int32).map_err(pe)?.into_date(),
        NqDtype::Datetime => s.into_datetime(time_unit(spec.time_unit), time_zone(spec.time_zone)?),
        NqDtype::Duration => s.into_duration(time_unit(spec.time_unit)),
        NqDtype::Time => s.into_time(),
        _ => return Err("not a temporal dtype".into()),
    })
}

/// A temporal series from physical i64 values (see `nq_df_column_physical`);
/// `valid` may be NULL (no nulls).
#[no_mangle]
pub unsafe extern "C" fn nq_series_new_temporal(
    name: *const c_char,
    values: *const i64,
    valid: *const bool,
    n: usize,
    spec: *const NqDtypeSpec,
) -> *mut Series {
    boxed(guard(|| {
        let valid = if valid.is_null() { None } else { Some(slice(valid, n)?) };
        physical_series(cstr(name)?, slice(values, n)?, valid, borrow(spec, "dtype")?)
    }))
}

/// A temporal literal from one physical value.
#[no_mangle]
pub unsafe extern "C" fn nq_expr_lit_temporal(v: i64, spec: *const NqDtypeSpec) -> *mut Expr {
    boxed(guard(|| {
        let s = physical_series("literal", &[v], None, borrow(spec, "dtype")?)?;
        let av = s.get(0).map_err(pe)?.into_static();
        Ok(Scalar::new(s.dtype().clone(), av).lit())
    }))
}

/// Physical representation (`to_physical`).
#[no_mangle]
pub unsafe extern "C" fn nq_expr_to_physical(e: *const Expr) -> *mut Expr {
    boxed(guard(|| Ok(borrow(e, "expression")?.clone().to_physical())))
}

/// Closed windows. Keep in sync with `NqClosedWindow` in nanuq/ffi.nim.
#[repr(C)]
#[derive(Clone, Copy)]
pub enum NqClosedWindow {
    Left = 0,
    Right,
    Both,
    None,
}

fn closed_window(c: NqClosedWindow) -> ClosedWindow {
    match c {
        NqClosedWindow::Left => ClosedWindow::Left,
        NqClosedWindow::Right => ClosedWindow::Right,
        NqClosedWindow::Both => ClosedWindow::Both,
        NqClosedWindow::None => ClosedWindow::None,
    }
}

/// `date_range` (`datetime = false`) or `datetime_range` from `start` to `end`
/// every `interval` (a Polars duration string such as "1d" or "1mo2d").
#[no_mangle]
pub unsafe extern "C" fn nq_expr_date_range(
    start: *const Expr,
    end: *const Expr,
    interval: *const c_char,
    closed: NqClosedWindow,
    datetime: bool,
    has_time_unit: bool,
    tu: NqTimeUnit,
    tz: *const c_char,
) -> *mut Expr {
    boxed(guard(|| {
        let start = borrow(start, "expression")?.clone();
        let end = borrow(end, "expression")?.clone();
        let every = polars::prelude::Duration::try_parse(cstr(interval)?).map_err(pe)?;
        if datetime {
            polars::lazy::dsl::datetime_range(
                Some(start),
                Some(end),
                Some(every),
                None,
                closed_window(closed),
                has_time_unit.then(|| time_unit(tu)),
                time_zone(tz)?,
            )
            .map_err(pe)
        } else {
            polars::lazy::dsl::date_range(Some(start), Some(end), Some(every), None, closed_window(closed)).map_err(pe)
        }
    }))
}

/// `duration(weeks, days, hours, minutes, seconds, milliseconds, microseconds,
/// nanoseconds)`: `parts` holds those 8 expressions.
#[no_mangle]
pub unsafe extern "C" fn nq_expr_duration(parts: *const *const Expr, tu: NqTimeUnit) -> *mut Expr {
    boxed(guard(|| {
        let p = exprs(parts, 8)?;
        let mut it = p.into_iter();
        let mut next = || it.next().unwrap();
        Ok(polars::lazy::dsl::duration(DurationArgs {
            weeks: next(),
            days: next(),
            hours: next(),
            minutes: next(),
            seconds: next(),
            milliseconds: next(),
            microseconds: next(),
            nanoseconds: next(),
            time_unit: time_unit(tu),
        }))
    }))
}

/// A Date from year, month and day expressions (Polars' `date`): a Datetime
/// built from the parts, cast to Date.
#[no_mangle]
pub unsafe extern "C" fn nq_expr_date(
    year: *const Expr,
    month: *const Expr,
    day: *const Expr,
) -> *mut Expr {
    boxed(guard(|| {
        let args = DatetimeArgs::new(
            borrow(year, "year")?.clone(),
            borrow(month, "month")?.clone(),
            borrow(day, "day")?.clone(),
        );
        Ok(polars::lazy::dsl::datetime(args).cast(DataType::Date))
    }))
}

// ---------------------------------------------------------------------------
// Parsing strings into temporal values, and the dt namespace
// ---------------------------------------------------------------------------

/// `str.strptime` into the dtype `spec` (Date, Datetime or Time). `format` may
/// be NULL or "" (inferred); `ambiguous` is "raise", "earliest", "latest" or
/// "null".
#[no_mangle]
pub unsafe extern "C" fn nq_expr_strptime(
    e: *const Expr,
    spec: *const NqDtypeSpec,
    format: *const c_char,
    strict: bool,
    exact: bool,
    cache: bool,
    ambiguous: *const c_char,
) -> *mut Expr {
    boxed(guard(|| {
        let dt = dtype_from_spec(borrow(spec, "dtype")?)?;
        let fmt = if format.is_null() { "" } else { cstr(format)? };
        let options = StrptimeOptions {
            format: (!fmt.is_empty()).then(|| fmt.into()),
            strict,
            exact,
            cache,
        };
        let e = borrow(e, "expression")?.clone();
        Ok(e.str().strptime(dt, options, lit(cstr(ambiguous)?)))
    }))
}

/// dt functions. Keep in sync with `NqDtOp` in nanuq/ffi.nim.
#[repr(C)]
#[derive(Clone, Copy)]
pub enum NqDtOp {
    Year = 0,
    IsoYear,
    Quarter,
    Month,
    Week,
    Weekday,
    Day,
    OrdinalDay,
    Hour,
    Minute,
    Second,
    Millisecond,
    Microsecond,
    Nanosecond,
    Date,
    Time,
    IsLeapYear,
    DaysInMonth,
    MonthStart,
    MonthEnd,
    Timestamp,
    CastTimeUnit,
    ToString,
    Truncate,
    Round,
    OffsetBy,
    ConvertTimeZone,
    ReplaceTimeZone,
    Combine,
    TotalDays,
    TotalHours,
    TotalMinutes,
    TotalSeconds,
    TotalMilliseconds,
    TotalMicroseconds,
    TotalNanoseconds,
}

/// One entry point for the `dt` namespace: `a` is an expression argument
/// (interval, offset, time, ambiguous), `s` a string argument (format, time
/// zone), `flag` the `fractional` option, `tu` a time unit, and `non_existent`
/// 0 for null, 1 for raise.
#[no_mangle]
pub unsafe extern "C" fn nq_expr_dt(
    e: *const Expr,
    op: NqDtOp,
    a: *const Expr,
    s: *const c_char,
    flag: bool,
    tu: NqTimeUnit,
    non_existent: i32,
) -> *mut Expr {
    boxed(guard(|| {
        let ns = borrow(e, "expression")?.clone().dt();
        let a = opt_expr(a)?;
        let s = if s.is_null() { "" } else { cstr(s)? };
        let tu = time_unit(tu);
        Ok(match op {
            NqDtOp::Year => ns.year(),
            NqDtOp::IsoYear => ns.iso_year(),
            NqDtOp::Quarter => ns.quarter(),
            NqDtOp::Month => ns.month(),
            NqDtOp::Week => ns.week(),
            NqDtOp::Weekday => ns.weekday(),
            NqDtOp::Day => ns.day(),
            NqDtOp::OrdinalDay => ns.ordinal_day(),
            NqDtOp::Hour => ns.hour(),
            NqDtOp::Minute => ns.minute(),
            NqDtOp::Second => ns.second(),
            NqDtOp::Millisecond => ns.millisecond(),
            NqDtOp::Microsecond => ns.microsecond(),
            NqDtOp::Nanosecond => ns.nanosecond(),
            NqDtOp::Date => ns.date(),
            NqDtOp::Time => ns.time(),
            NqDtOp::IsLeapYear => ns.is_leap_year(),
            NqDtOp::DaysInMonth => ns.days_in_month(),
            NqDtOp::MonthStart => ns.month_start(),
            NqDtOp::MonthEnd => ns.month_end(),
            NqDtOp::Timestamp => ns.timestamp(tu),
            NqDtOp::CastTimeUnit => ns.cast_time_unit(tu),
            NqDtOp::ToString => ns.to_string(s),
            NqDtOp::Truncate => ns.truncate(a),
            NqDtOp::Round => ns.round(a),
            NqDtOp::OffsetBy => ns.offset_by(a),
            NqDtOp::ConvertTimeZone => {
                let tz = time_zone_req(s)?;
                ns.convert_time_zone(tz)
            }
            NqDtOp::ReplaceTimeZone => {
                let tz = if s.is_empty() { None } else { Some(time_zone_req(s)?) };
                let ne = if non_existent == 1 { NonExistent::Raise } else { NonExistent::Null };
                ns.replace_time_zone(tz, a, ne)
            }
            NqDtOp::Combine => ns.combine(a, tu),
            NqDtOp::TotalDays => ns.total_days(flag),
            NqDtOp::TotalHours => ns.total_hours(flag),
            NqDtOp::TotalMinutes => ns.total_minutes(flag),
            NqDtOp::TotalSeconds => ns.total_seconds(flag),
            NqDtOp::TotalMilliseconds => ns.total_milliseconds(flag),
            NqDtOp::TotalMicroseconds => ns.total_microseconds(flag),
            NqDtOp::TotalNanoseconds => ns.total_nanoseconds(flag),
        })
    }))
}

fn time_zone_req(s: &str) -> Result<TimeZone, String> {
    TimeZone::opt_try_new(Some(s))
        .map_err(pe)?
        .ok_or_else(|| "a time zone is required".to_string())
}

// ---------------------------------------------------------------------------
// 0.4: math functions (add-expr-math)
// ---------------------------------------------------------------------------

/// Expression functions of two expressions. Keep in sync with `NqBinaryFn` in
/// nanuq/ffi.nim.
#[repr(C)]
#[derive(Clone, Copy)]
pub enum NqBinaryFn {
    Log = 0,
    Arctan2,
    Dot,
    FillNan,
    InterpolateBy,
    Gather,
    TopK,
    BottomK,
    IndexOf,
    SearchSortedAny,
    SearchSortedLeft,
    SearchSortedRight,
}

#[no_mangle]
pub unsafe extern "C" fn nq_expr_binary_fn(a: *const Expr, b: *const Expr, op: NqBinaryFn) -> *mut Expr {
    boxed(guard(|| {
        let a = borrow(a, "expression")?.clone();
        let b = borrow(b, "expression")?.clone();
        Ok(match op {
            NqBinaryFn::Log => a.log(b),
            NqBinaryFn::Arctan2 => a.arctan2(b),
            NqBinaryFn::Dot => a.dot(b),
            NqBinaryFn::FillNan => a.fill_nan(b),
            NqBinaryFn::InterpolateBy => a.interpolate_by(b),
            NqBinaryFn::Gather => a.gather(b, false),
            NqBinaryFn::TopK => a.top_k(b),
            NqBinaryFn::BottomK => a.bottom_k(b),
            NqBinaryFn::IndexOf => a.index_of(b),
            NqBinaryFn::SearchSortedAny => a.search_sorted(b, SearchSortedSide::Any, false),
            NqBinaryFn::SearchSortedLeft => a.search_sorted(b, SearchSortedSide::Left, false),
            NqBinaryFn::SearchSortedRight => a.search_sorted(b, SearchSortedSide::Right, false),
        })
    }))
}

/// `clip` with either bound optional (null pointer = no bound).
#[no_mangle]
pub unsafe extern "C" fn nq_expr_clip(e: *const Expr, lo: *const Expr, hi: *const Expr) -> *mut Expr {
    boxed(guard(|| {
        let e = borrow(e, "expression")?.clone();
        let lo = if lo.is_null() { None } else { Some(borrow(lo, "expression")?.clone()) };
        let hi = if hi.is_null() { None } else { Some(borrow(hi, "expression")?.clone()) };
        Ok(match (lo, hi) {
            (Some(l), Some(h)) => e.clip(l, h),
            (Some(l), None) => e.clip_min(l),
            (None, Some(h)) => e.clip_max(h),
            (None, None) => e,
        })
    }))
}

// ---------------------------------------------------------------------------
// 0.4: shift, diff, cumulative functions (add-cumulative-and-shift)
// ---------------------------------------------------------------------------

/// `fill` may be null: then the empty rows are null.
#[no_mangle]
pub unsafe extern "C" fn nq_expr_shift(e: *const Expr, n: i64, fill: *const Expr) -> *mut Expr {
    boxed(guard(|| {
        let e = borrow(e, "expression")?.clone();
        Ok(if fill.is_null() {
            e.shift(lit(n))
        } else {
            e.shift_and_fill(lit(n), borrow(fill, "expression")?.clone())
        })
    }))
}

#[no_mangle]
pub unsafe extern "C" fn nq_expr_diff(e: *const Expr, n: i64, drop: bool) -> *mut Expr {
    boxed(guard(|| {
        let nb = if drop { polars_core::series::ops::NullBehavior::Drop } else { polars_core::series::ops::NullBehavior::Ignore };
        Ok(borrow(e, "expression")?.clone().diff(lit(n), nb))
    }))
}

#[no_mangle]
pub unsafe extern "C" fn nq_expr_pct_change(e: *const Expr, n: i64) -> *mut Expr {
    boxed(guard(|| Ok(borrow(e, "expression")?.clone().pct_change(lit(n)))))
}

/// Keep in sync with `NqCum` in nanuq/ffi.nim.
#[repr(C)]
#[derive(Clone, Copy)]
pub enum NqCum {
    Sum = 0,
    Prod,
    Min,
    Max,
    Count,
}

#[no_mangle]
pub unsafe extern "C" fn nq_expr_cum(e: *const Expr, op: NqCum, reverse: bool) -> *mut Expr {
    boxed(guard(|| {
        let e = borrow(e, "expression")?.clone();
        Ok(match op {
            NqCum::Sum => e.cum_sum(reverse),
            NqCum::Prod => e.cum_prod(reverse),
            NqCum::Min => e.cum_min(reverse),
            NqCum::Max => e.cum_max(reverse),
            NqCum::Count => e.cum_count(reverse),
        })
    }))
}

/// Skewness (`kurtosis = false`) or kurtosis.
#[no_mangle]
pub unsafe extern "C" fn nq_expr_moment(e: *const Expr, kurtosis: bool, fisher: bool, bias: bool) -> *mut Expr {
    boxed(guard(|| {
        let e = borrow(e, "expression")?.clone();
        Ok(if kurtosis { e.kurtosis(fisher, bias) } else { e.skew(bias) })
    }))
}

// ---------------------------------------------------------------------------
// 0.4: rolling windows, ewm, interpolate (add-rolling-and-ewm)
// ---------------------------------------------------------------------------

/// Keep in sync with `NqRolling` in nanuq/ffi.nim.
#[repr(C)]
#[derive(Clone, Copy, PartialEq)]
pub enum NqRolling {
    Sum = 0,
    Mean,
    Min,
    Max,
    Std,
    Var,
    Median,
    Quantile,
}

fn quantile_method(m: NqQuantileMethod) -> QuantileMethod {
    match m {
        NqQuantileMethod::Nearest => QuantileMethod::Nearest,
        NqQuantileMethod::Lower => QuantileMethod::Lower,
        NqQuantileMethod::Higher => QuantileMethod::Higher,
        NqQuantileMethod::Midpoint => QuantileMethod::Midpoint,
        NqQuantileMethod::Linear => QuantileMethod::Linear,
        NqQuantileMethod::Equiprobable => QuantileMethod::Equiprobable,
    }
}

fn var_params(op: NqRolling, ddof: u8) -> Option<polars::prelude::RollingFnParams> {
    match op {
        NqRolling::Std | NqRolling::Var => Some(polars::prelude::RollingFnParams::Var(
            polars::prelude::RollingVarParams { ddof },
        )),
        _ => None,
    }
}

/// Fixed-size rolling window (`window` rows). `weights` may be null.
#[no_mangle]
pub unsafe extern "C" fn nq_expr_rolling(
    e: *const Expr,
    op: NqRolling,
    window: usize,
    min_samples: usize,
    center: bool,
    weights: *const f64,
    n_weights: usize,
    quantile: f64,
    method: NqQuantileMethod,
    ddof: u8,
) -> *mut Expr {
    boxed(guard(|| {
        let e = borrow(e, "expression")?.clone();
        let weights = if weights.is_null() || n_weights == 0 {
            None
        } else {
            Some(std::slice::from_raw_parts(weights, n_weights).to_vec())
        };
        let opts = RollingOptionsFixedWindow {
            window_size: window,
            min_periods: min_samples,
            weights,
            center,
            fn_params: var_params(op, ddof),
        };
        Ok(match op {
            NqRolling::Sum => e.rolling_sum(opts),
            NqRolling::Mean => e.rolling_mean(opts),
            NqRolling::Min => e.rolling_min(opts),
            NqRolling::Max => e.rolling_max(opts),
            NqRolling::Std => e.rolling_std(opts),
            NqRolling::Var => e.rolling_var(opts),
            NqRolling::Median => e.rolling_median(opts),
            NqRolling::Quantile => e.rolling_quantile(quantile_method(method), quantile, opts),
        })
    }))
}

/// Rolling window over a temporal or integer column `by`, `window` a duration string.
#[no_mangle]
pub unsafe extern "C" fn nq_expr_rolling_by(
    e: *const Expr,
    by: *const Expr,
    op: NqRolling,
    window: *const c_char,
    min_samples: usize,
    closed: NqClosedWindow,
    quantile: f64,
    method: NqQuantileMethod,
    ddof: u8,
) -> *mut Expr {
    boxed(guard(|| {
        let e = borrow(e, "expression")?.clone();
        let by = borrow(by, "expression")?.clone();
        let opts = RollingOptionsDynamicWindow {
            window_size: polars::prelude::Duration::try_parse(cstr(window)?).map_err(pe)?,
            min_periods: min_samples,
            closed_window: closed_window(closed),
            fn_params: var_params(op, ddof),
        };
        Ok(match op {
            NqRolling::Sum => e.rolling_sum_by(by, opts),
            NqRolling::Mean => e.rolling_mean_by(by, opts),
            NqRolling::Min => e.rolling_min_by(by, opts),
            NqRolling::Max => e.rolling_max_by(by, opts),
            NqRolling::Std => e.rolling_std_by(by, opts),
            NqRolling::Var => e.rolling_var_by(by, opts),
            NqRolling::Median => e.rolling_median_by(by, opts),
            NqRolling::Quantile => e.rolling_quantile_by(by, quantile_method(method), quantile, opts),
        })
    }))
}

/// Exponentially weighted mean (0), std (1) or var (2).
#[no_mangle]
pub unsafe extern "C" fn nq_expr_ewm(
    e: *const Expr,
    op: u8,
    alpha: f64,
    adjust: bool,
    bias: bool,
    min_samples: usize,
    ignore_nulls: bool,
) -> *mut Expr {
    boxed(guard(|| {
        let e = borrow(e, "expression")?.clone();
        let opts = EWMOptions { alpha, adjust, bias, min_periods: min_samples, ignore_nulls };
        Ok(match op {
            0 => e.ewm_mean(opts),
            1 => e.ewm_std(opts),
            _ => e.ewm_var(opts),
        })
    }))
}

#[no_mangle]
pub unsafe extern "C" fn nq_expr_interpolate(e: *const Expr, nearest: bool) -> *mut Expr {
    boxed(guard(|| {
        let m = if nearest { InterpolationMethod::Nearest } else { InterpolationMethod::Linear };
        Ok(borrow(e, "expression")?.clone().interpolate(m))
    }))
}

// ---------------------------------------------------------------------------
// 0.4: sorting, selecting and counting values (add-value-functions)
// ---------------------------------------------------------------------------

#[no_mangle]
pub unsafe extern "C" fn nq_expr_sort(e: *const Expr, descending: bool, nulls_last: bool, arg: bool) -> *mut Expr {
    boxed(guard(|| {
        let e = borrow(e, "expression")?.clone();
        Ok(if arg {
            e.arg_sort(descending, nulls_last)
        } else {
            e.sort(SortOptions::default().with_order_descending(descending).with_nulls_last(nulls_last))
        })
    }))
}

#[no_mangle]
pub unsafe extern "C" fn nq_expr_sort_by(
    e: *const Expr,
    by: *const *const Expr,
    n: usize,
    descending: *const bool,
    n_desc: usize,
) -> *mut Expr {
    boxed(guard(|| {
        let by = exprs(by, n)?;
        let mut desc = slice(descending, n_desc)?.to_vec();
        if desc.is_empty() {
            desc = vec![false; by.len()];
        } else if desc.len() == 1 {
            desc = vec![desc[0]; by.len()];
        } else if desc.len() != by.len() {
            return Err(format!("sortBy got {} values for descending but {} keys", desc.len(), by.len()));
        }
        let opts = SortMultipleOptions::default().with_order_descending_multi(desc);
        Ok(borrow(e, "expression")?.clone().sort_by(by, opts))
    }))
}

/// `top_k_by` (`bottom = false`) or `bottom_k_by` with one `reverse` flag per key.
#[no_mangle]
pub unsafe extern "C" fn nq_expr_top_k_by(
    e: *const Expr,
    k: usize,
    by: *const *const Expr,
    n: usize,
    reverse: *const bool,
    n_rev: usize,
    bottom: bool,
) -> *mut Expr {
    boxed(guard(|| {
        let by = exprs(by, n)?;
        let mut rev = slice(reverse, n_rev)?.to_vec();
        if rev.is_empty() {
            rev = vec![false; by.len()];
        } else if rev.len() == 1 {
            rev = vec![rev[0]; by.len()];
        }
        let e = borrow(e, "expression")?.clone();
        Ok(if bottom { e.bottom_k_by(lit(k as u64), by, rev) } else { e.top_k_by(lit(k as u64), by, rev) })
    }))
}

#[no_mangle]
pub unsafe extern "C" fn nq_expr_slice(e: *const Expr, offset: i64, len: i64) -> *mut Expr {
    boxed(guard(|| {
        let e = borrow(e, "expression")?.clone();
        Ok(if len < 0 { e.slice(lit(offset), lit(u32::MAX as u64)) } else { e.slice(lit(offset), lit(len as u64)) })
    }))
}

#[no_mangle]
pub unsafe extern "C" fn nq_expr_gather_every(e: *const Expr, n: usize, offset: usize) -> *mut Expr {
    boxed(guard(|| Ok(borrow(e, "expression")?.clone().gather_every(n, offset))))
}

/// `replace` or `replace_strict` (`default` may be null).
#[no_mangle]
pub unsafe extern "C" fn nq_expr_replace(
    e: *const Expr,
    old: *const Expr,
    new: *const Expr,
    strict: bool,
    default: *const Expr,
) -> *mut Expr {
    boxed(guard(|| {
        let e = borrow(e, "expression")?.clone();
        let old = borrow(old, "expression")?.clone();
        let new = borrow(new, "expression")?.clone();
        Ok(if strict {
            let d = if default.is_null() { None } else { Some(borrow(default, "expression")?.clone()) };
            e.replace_strict(old, new, d, None::<DataTypeExpr>)
        } else {
            e.replace(old, new)
        })
    }))
}

/// `cut` at `breaks` (`quantile = false`) or `qcut` at quantiles `breaks`.
/// `labels` may be empty (Polars' interval labels).
#[no_mangle]
pub unsafe extern "C" fn nq_expr_cut(
    e: *const Expr,
    breaks: *const f64,
    n: usize,
    labels: *const *const c_char,
    n_labels: usize,
    left_closed: bool,
    quantile: bool,
    allow_duplicates: bool,
) -> *mut Expr {
    boxed(guard(|| {
        let e = borrow(e, "expression")?.clone();
        let breaks = slice(breaks, n)?.to_vec();
        let labels: Option<Vec<PlSmallStr>> = if n_labels == 0 {
            None
        } else {
            Some(names(labels, n_labels)?.into_iter().map(PlSmallStr::from_str).collect())
        };
        Ok(if quantile {
            e.qcut(breaks, labels, left_closed, allow_duplicates, false)
        } else {
            e.cut(breaks, labels, left_closed, false)
        })
    }))
}

/// Counts of each distinct value of `e`, as columns (value, `name`).
#[no_mangle]
pub unsafe extern "C" fn nq_lf_value_counts(
    lf_: *const LazyFrame,
    e: *const Expr,
    sort: bool,
    normalize: bool,
    name: *const c_char,
) -> *mut LazyFrame {
    boxed(guard(|| {
        let e = borrow(e, "expression")?.clone();
        let name = cstr(name)?;
        let vc = e.value_counts(sort, false, name, normalize).alias("__nq_vc");
        Ok(lf(lf_)?.select([vc]).unnest(cols(["__nq_vc"]), None))
    }))
}

// ---------------------------------------------------------------------------
// 0.4: horizontal functions, ranges, correlation (add-horizontal-and-ranges)
// ---------------------------------------------------------------------------

/// Keep in sync with `NqHorizontal` in nanuq/ffi.nim.
#[repr(C)]
#[derive(Clone, Copy)]
pub enum NqHorizontal {
    Sum = 0,
    Mean,
    Min,
    Max,
    All,
    Any,
    Coalesce,
}

#[no_mangle]
pub unsafe extern "C" fn nq_expr_horizontal(
    es: *const *const Expr,
    n: usize,
    op: NqHorizontal,
    ignore_nulls: bool,
) -> *mut Expr {
    boxed(guard(|| {
        let es = exprs(es, n)?;
        if es.is_empty() {
            return Err("horizontal functions need at least one expression".into());
        }
        match op {
            NqHorizontal::Sum => polars::lazy::dsl::sum_horizontal(es, ignore_nulls).map_err(pe),
            NqHorizontal::Mean => polars::lazy::dsl::mean_horizontal(es, ignore_nulls).map_err(pe),
            NqHorizontal::Min => polars::lazy::dsl::min_horizontal(es).map_err(pe),
            NqHorizontal::Max => polars::lazy::dsl::max_horizontal(es).map_err(pe),
            NqHorizontal::All => all_horizontal(es).map_err(pe),
            NqHorizontal::Any => any_horizontal(es).map_err(pe),
            NqHorizontal::Coalesce => Ok(coalesce(&es)),
        }
    }))
}

/// `int_range(start, end, step)` of type `spec`.
#[no_mangle]
pub unsafe extern "C" fn nq_expr_int_range(
    start: *const Expr,
    end: *const Expr,
    step: i64,
    spec: *const NqDtypeSpec,
) -> *mut Expr {
    boxed(guard(|| {
        let start = borrow(start, "expression")?.clone();
        let end = borrow(end, "expression")?.clone();
        let dt = dtype_from_spec(borrow(spec, "dtype")?)?;
        Ok(int_range(start, end, step, dt))
    }))
}

#[no_mangle]
pub unsafe extern "C" fn nq_expr_linear_space(
    start: *const Expr,
    end: *const Expr,
    num: *const Expr,
    closed: NqClosedInterval,
) -> *mut Expr {
    boxed(guard(|| {
        let start = borrow(start, "expression")?.clone();
        let end = borrow(end, "expression")?.clone();
        let num = borrow(num, "expression")?.clone();
        Ok(linear_space(start, end, num, closed_interval(closed)))
    }))
}

#[no_mangle]
pub unsafe extern "C" fn nq_expr_repeat(value: *const Expr, n: *const Expr) -> *mut Expr {
    boxed(guard(|| {
        let value = borrow(value, "expression")?.clone();
        let n = borrow(n, "expression")?.clone();
        Ok(repeat(value, n))
    }))
}

/// Pearson (0), Spearman (1) correlation, or covariance (2) with `ddof`.
#[no_mangle]
pub unsafe extern "C" fn nq_expr_corr(a: *const Expr, b: *const Expr, method: u8, ddof: u8, propagate_nans: bool) -> *mut Expr {
    boxed(guard(|| {
        let a = borrow(a, "expression")?.clone();
        let b = borrow(b, "expression")?.clone();
        Ok(match method {
            0 => pearson_corr(a, b),
            1 => spearman_rank_corr(a, b, propagate_nans),
            _ => cov(a, b, ddof),
        })
    }))
}

fn closed_interval(c: NqClosedInterval) -> ClosedInterval {
    match c {
        NqClosedInterval::Both => ClosedInterval::Both,
        NqClosedInterval::Left => ClosedInterval::Left,
        NqClosedInterval::Right => ClosedInterval::Right,
        NqClosedInterval::None => ClosedInterval::None,
    }
}

// ---------------------------------------------------------------------------
// 0.4: reshaping (add-reshaping)
// ---------------------------------------------------------------------------

unsafe fn name_selector(p: *const *const c_char, n: usize) -> Result<Selector, String> {
    Ok(by_name(names(p, n)?.into_iter().map(PlSmallStr::from_str).collect::<Vec<_>>(), true, false))
}

/// Lazy pivot: `on_columns` holds the values of the `on` columns that become
/// columns. `agg` is an expression over `element()`.
#[no_mangle]
pub unsafe extern "C" fn nq_lf_pivot(
    lf_: *const LazyFrame,
    on: *const *const c_char,
    n_on: usize,
    on_columns: *const DataFrame,
    index: *const *const c_char,
    n_index: usize,
    values: *const *const c_char,
    n_values: usize,
    agg: *const Expr,
    maintain_order: bool,
    separator: *const c_char,
) -> *mut LazyFrame {
    boxed(guard(|| {
        let on_cols = Arc::new(borrow(on_columns, "DataFrame")?.clone());
        Ok(lf(lf_)?.pivot(
            name_selector(on, n_on)?,
            on_cols,
            name_selector(index, n_index)?,
            name_selector(values, n_values)?,
            borrow(agg, "expression")?.clone(),
            maintain_order,
            PlSmallStr::from_str(cstr(separator)?),
            polars_core::frame::PivotColumnNaming::Auto,
        ))
    }))
}

/// `on` empty means every column not in `index`.
#[no_mangle]
pub unsafe extern "C" fn nq_lf_unpivot(
    lf_: *const LazyFrame,
    on: *const *const c_char,
    n_on: usize,
    index: *const *const c_char,
    n_index: usize,
    variable_name: *const c_char,
    value_name: *const c_char,
) -> *mut LazyFrame {
    boxed(guard(|| {
        let args = UnpivotArgsDSL {
            on: if n_on == 0 { None } else { Some(name_selector(on, n_on)?) },
            index: name_selector(index, n_index)?,
            variable_name: Some(PlSmallStr::from_str(cstr(variable_name)?)),
            value_name: Some(PlSmallStr::from_str(cstr(value_name)?)),
        };
        Ok(lf(lf_)?.unpivot(args))
    }))
}

/// `keep_names_as` may be null; `new_names` may be empty (column_0, ...).
#[no_mangle]
pub unsafe extern "C" fn nq_df_transpose(
    df: *const DataFrame,
    keep_names_as: *const c_char,
    new_names: *const *const c_char,
    n_names: usize,
) -> *mut DataFrame {
    boxed(guard(|| {
        let mut df = borrow(df, "DataFrame")?.clone();
        let keep = if keep_names_as.is_null() { None } else { Some(cstr(keep_names_as)?) };
        let names: Vec<String> = names(new_names, n_names)?.into_iter().map(String::from).collect();
        let new = if names.is_empty() { None } else { Some(either::Either::Right(names)) };
        df.transpose(keep, new).map_err(pe)
    }))
}

/// Splits `df` by the `by` columns. Returns an array of `*out_len` frames, to
/// be released with `nq_df_array_free` after taking ownership of each frame.
#[no_mangle]
pub unsafe extern "C" fn nq_df_partition_by(
    df: *const DataFrame,
    by: *const *const c_char,
    n: usize,
    maintain_order: bool,
    include_key: bool,
    out_len: *mut usize,
) -> *mut *mut DataFrame {
    let parts = guard(|| {
        let df = borrow(df, "DataFrame")?;
        let by: Vec<PlSmallStr> = names(by, n)?.into_iter().map(PlSmallStr::from_str).collect();
        if by.is_empty() {
            return Err("partitionBy needs at least one column".into());
        }
        if maintain_order {
            df.partition_by_stable(by, include_key).map_err(pe)
        } else {
            df.partition_by(by, include_key).map_err(pe)
        }
    });
    match parts {
        None => ptr::null_mut(),
        Some(parts) => {
            let ptrs: Vec<*mut DataFrame> = parts.into_iter().map(|d| Box::into_raw(Box::new(d))).collect();
            *out_len = ptrs.len();
            Box::into_raw(ptrs.into_boxed_slice()) as *mut *mut DataFrame
        }
    }
}

/// Frees the array returned by `nq_df_partition_by` (not the frames in it).
#[no_mangle]
pub unsafe extern "C" fn nq_df_array_free(p: *mut *mut DataFrame, len: usize) {
    if !p.is_null() {
        drop(Box::from_raw(std::ptr::slice_from_raw_parts_mut(p, len)));
    }
}

/// One-hot encoding of the `n` named columns (all when `n == 0`).
#[no_mangle]
pub unsafe extern "C" fn nq_df_to_dummies(
    df: *const DataFrame,
    columns: *const *const c_char,
    n: usize,
    separator: *const c_char,
    drop_first: bool,
    drop_nulls: bool,
) -> *mut DataFrame {
    boxed(guard(|| {
        let df = borrow(df, "DataFrame")?;
        let cols = names(columns, n)?;
        let sep = cstr(separator)?;
        if cols.is_empty() {
            df.to_dummies(Some(sep), drop_first, drop_nulls).map_err(pe)
        } else {
            df.columns_to_dummies(cols, Some(sep), drop_first, drop_nulls).map_err(pe)
        }
    }))
}

#[no_mangle]
pub unsafe extern "C" fn nq_expr_element() -> *mut Expr {
    boxed(guard(|| Ok(element())))
}

/// `item(allow_empty)`: the single value of a group (errors on more than one).
#[no_mangle]
pub unsafe extern "C" fn nq_expr_item(e: *const Expr, allow_empty: bool) -> *mut Expr {
    boxed(guard(|| Ok(borrow(e, "expression")?.clone().item(allow_empty))))
}

// ---------------------------------------------------------------------------
// 0.4: time-based grouping and as-of joins (add-dynamic-group-by)
// ---------------------------------------------------------------------------

unsafe fn duration_arg(s: *const c_char) -> Result<polars::prelude::Duration, String> {
    polars::prelude::Duration::try_parse(cstr(s)?).map_err(pe)
}

/// Keep in sync with `NqLabel` and `NqStartBy` in nanuq/ffi.nim.
#[repr(C)]
#[derive(Clone, Copy)]
pub enum NqLabel {
    Left = 0,
    Right,
    DataPoint,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub enum NqStartBy {
    WindowBound = 0,
    DataPoint,
    Monday,
    Tuesday,
    Wednesday,
    Thursday,
    Friday,
    Saturday,
    Sunday,
}

#[no_mangle]
pub unsafe extern "C" fn nq_lf_group_by_dynamic_agg(
    lf_: *const LazyFrame,
    index: *const Expr,
    by: *const *const Expr,
    nby: usize,
    every: *const c_char,
    period: *const c_char,
    offset: *const c_char,
    label: NqLabel,
    include_boundaries: bool,
    closed: NqClosedWindow,
    start_by: NqStartBy,
    aggs: *const *const Expr,
    naggs: usize,
) -> *mut LazyFrame {
    boxed(guard(|| {
        let opts = DynamicGroupOptions {
            index_column: "".into(),
            every: duration_arg(every)?,
            period: duration_arg(period)?,
            offset: duration_arg(offset)?,
            label: match label {
                NqLabel::Left => Label::Left,
                NqLabel::Right => Label::Right,
                NqLabel::DataPoint => Label::DataPoint,
            },
            include_boundaries,
            closed_window: closed_window(closed),
            start_by: match start_by {
                NqStartBy::WindowBound => StartBy::WindowBound,
                NqStartBy::DataPoint => StartBy::DataPoint,
                NqStartBy::Monday => StartBy::Monday,
                NqStartBy::Tuesday => StartBy::Tuesday,
                NqStartBy::Wednesday => StartBy::Wednesday,
                NqStartBy::Thursday => StartBy::Thursday,
                NqStartBy::Friday => StartBy::Friday,
                NqStartBy::Saturday => StartBy::Saturday,
                NqStartBy::Sunday => StartBy::Sunday,
            },
        };
        let index = borrow(index, "expression")?.clone();
        Ok(lf(lf_)?
            .group_by_dynamic(index, exprs(by, nby)?, opts)
            .agg(exprs(aggs, naggs)?))
    }))
}

#[no_mangle]
pub unsafe extern "C" fn nq_lf_rolling_agg(
    lf_: *const LazyFrame,
    index: *const Expr,
    by: *const *const Expr,
    nby: usize,
    period: *const c_char,
    offset: *const c_char,
    closed: NqClosedWindow,
    aggs: *const *const Expr,
    naggs: usize,
) -> *mut LazyFrame {
    boxed(guard(|| {
        let opts = RollingGroupOptions {
            index_column: "".into(),
            period: duration_arg(period)?,
            offset: duration_arg(offset)?,
            closed_window: closed_window(closed),
        };
        let index = borrow(index, "expression")?.clone();
        Ok(lf(lf_)?.rolling(index, exprs(by, nby)?, opts).agg(exprs(aggs, naggs)?))
    }))
}

/// As-of join. `tolerance_kind`: 0 none, 1 duration string `tol_str`, 2 integer
/// `tol_int`, 3 float `tol_float`.
#[no_mangle]
pub unsafe extern "C" fn nq_lf_join_asof(
    left_: *const LazyFrame,
    right_: *const LazyFrame,
    left_on: *const Expr,
    right_on: *const Expr,
    by_left: *const *const c_char,
    n_by_left: usize,
    by_right: *const *const c_char,
    n_by_right: usize,
    strategy: u8,
    suffix: *const c_char,
    tolerance_kind: u8,
    tol_str: *const c_char,
    tol_int: i64,
    tol_float: f64,
    allow_exact_matches: bool,
    check_sortedness: bool,
    coalesce: bool,
) -> *mut LazyFrame {
    boxed(guard(|| {
        let to_names = |v: Vec<&str>| -> Option<Vec<PlSmallStr>> {
            (!v.is_empty()).then(|| v.into_iter().map(PlSmallStr::from_str).collect())
        };
        let left_by = to_names(names(by_left, n_by_left)?);
        let right_by = to_names(names(by_right, n_by_right)?);
        if left_by.as_ref().map(|v| v.len()) != right_by.as_ref().map(|v| v.len()) {
            return Err("joinAsof needs as many `by` columns on both sides".into());
        }
        let opts = AsOfOptions {
            strategy: match strategy {
                0 => AsofStrategy::Backward,
                1 => AsofStrategy::Forward,
                _ => AsofStrategy::Nearest,
            },
            tolerance: match tolerance_kind {
                2 => Some(Scalar::from(tol_int)),
                3 => Some(Scalar::from(tol_float)),
                _ => None,
            },
            tolerance_str: if tolerance_kind == 1 { Some(PlSmallStr::from_str(cstr(tol_str)?)) } else { None },
            left_by,
            right_by,
            allow_eq: allow_exact_matches,
            check_sortedness,
        };
        let mut args = JoinArgs::new(JoinType::AsOf(Box::new(opts)));
        args.suffix = Some(cstr(suffix)?.into());
        args.coalesce = if coalesce { JoinCoalesce::CoalesceColumns } else { JoinCoalesce::KeepColumns };
        let l = borrow(left_on, "expression")?.clone();
        let r = borrow(right_on, "expression")?.clone();
        Ok(lf(left_)?.join(lf(right_)?, [l], [r], args))
    }))
}

/// A Series as a column literal (not imploded into one list value, unlike
/// `nq_expr_lit_series`).
#[no_mangle]
pub unsafe extern "C" fn nq_expr_lit_values(s: *const Series) -> *mut Expr {
    boxed(guard(|| Ok(lit(borrow(s, "Series")?.clone()))))
}

// ---------------------------------------------------------------------------
// 0.4: Series (add-series-api)
// ---------------------------------------------------------------------------

#[no_mangle]
pub unsafe extern "C" fn nq_df_get_column(df: *const DataFrame, name: *const c_char) -> *mut Series {
    boxed(guard(|| {
        let df = borrow(df, "DataFrame")?;
        Ok(df.column(cstr(name)?).map_err(pe)?.as_materialized_series().clone())
    }))
}

#[no_mangle]
pub unsafe extern "C" fn nq_df_to_series(df: *const DataFrame, idx: usize) -> *mut Series {
    boxed(guard(|| {
        let df = borrow(df, "DataFrame")?;
        let c = df
            .columns()
            .get(idx)
            .ok_or_else(|| format!("column index {idx} out of bounds"))?;
        Ok(c.as_materialized_series().clone())
    }))
}

#[no_mangle]
pub unsafe extern "C" fn nq_series_to_frame(s: *const Series) -> *mut DataFrame {
    boxed(guard(|| Ok(borrow(s, "Series")?.clone().into_frame())))
}

#[no_mangle]
pub unsafe extern "C" fn nq_series_name(s: *const Series) -> *mut c_char {
    guard(|| Ok(to_c_string(borrow(s, "Series")?.name().to_string()))).unwrap_or(ptr::null_mut())
}

#[no_mangle]
pub unsafe extern "C" fn nq_series_len(s: *const Series) -> usize {
    guard(|| Ok(borrow(s, "Series")?.len())).unwrap_or(0)
}

#[no_mangle]
pub unsafe extern "C" fn nq_series_rename(s: *const Series, name: *const c_char) -> *mut Series {
    boxed(guard(|| {
        let mut s = borrow(s, "Series")?.clone();
        s.rename(PlSmallStr::from_str(cstr(name)?));
        Ok(s)
    }))
}

#[no_mangle]
pub unsafe extern "C" fn nq_series_to_string(s: *const Series) -> *mut c_char {
    guard(|| Ok(to_c_string(format!("{}", borrow(s, "Series")?)))).unwrap_or(ptr::null_mut())
}

// ---------------------------------------------------------------------------
// Frame top k, and float display precision (0.4)
// ---------------------------------------------------------------------------

/// The `k` rows with the largest (`bottom`: smallest) values of the `by`
/// expressions; `reverse` swaps the direction, as in Python's `top_k`.
#[no_mangle]
pub unsafe extern "C" fn nq_lf_top_k(
    lf_: *const LazyFrame,
    k: usize,
    by: *const *const Expr,
    nby: usize,
    reverse: bool,
    bottom: bool,
) -> *mut LazyFrame {
    boxed(guard(|| {
        let by = exprs(by, nby)?;
        if by.is_empty() {
            return Err("topK needs at least one `by` column".into());
        }
        let opts = SortMultipleOptions::default().with_maintain_order(true);
        let lf = lf(lf_)?;
        Ok(if bottom != reverse {
            lf.bottom_k(k as IdxSize, by, opts)
        } else {
            lf.top_k(k as IdxSize, by, opts)
        })
    }))
}

/// Decimal places when floats print; negative restores Polars' default.
#[no_mangle]
pub extern "C" fn nq_set_float_precision(n: i32) {
    polars_core::fmt::set_float_precision((n >= 0).then_some(n as usize));
}

/// The current float precision, or -1 for Polars' default.
#[no_mangle]
pub extern "C" fn nq_get_float_precision() -> i32 {
    polars_core::fmt::get_float_precision().map_or(-1, |n| n as i32)
}

// ---------------------------------------------------------------------------
// Null literal and boolean aggregations (0.4)
// ---------------------------------------------------------------------------

/// A null literal (Python's `pl.lit(None)`).
#[no_mangle]
pub extern "C" fn nq_expr_lit_null() -> *mut Expr {
    boxed(Some(lit(Null {})))
}

/// `any` (or `all` when `all` is true) of a boolean column, as an aggregation.
#[no_mangle]
pub unsafe extern "C" fn nq_expr_any_all(e: *const Expr, all: bool, ignore_nulls: bool) -> *mut Expr {
    boxed(guard(|| {
        let e = borrow(e, "expression")?.clone();
        Ok(if all { e.all(ignore_nulls) } else { e.any(ignore_nulls) })
    }))
}

// ---------------------------------------------------------------------------
// Data type handles (0.5): any data type, nested ones included, as an opaque
// `DataType`, so Nim can read and build types at any depth.
// ---------------------------------------------------------------------------

#[no_mangle]
pub unsafe extern "C" fn nq_dtype_free(d: *mut DataType) {
    if !d.is_null() {
        drop(Box::from_raw(d));
    }
}

/// The data type of a column, as a handle. Free with `nq_dtype_free`.
#[no_mangle]
pub unsafe extern "C" fn nq_df_column_dtype_handle(df: *const DataFrame, name: *const c_char) -> *mut DataType {
    boxed(guard(|| Ok(borrow(df, "DataFrame")?.column(cstr(name)?).map_err(pe)?.dtype().clone())))
}

/// A data type from a spec (any kind; nested kinds clone `spec.nested`).
#[no_mangle]
pub unsafe extern "C" fn nq_dtype_from_spec(spec: *const NqDtypeSpec) -> *mut DataType {
    boxed(guard(|| dtype_from_spec(borrow(spec, "dtype")?)))
}

#[no_mangle]
pub unsafe extern "C" fn nq_dtype_list(inner: *const DataType) -> *mut DataType {
    boxed(guard(|| Ok(DataType::List(Box::new(borrow(inner, "dtype")?.clone())))))
}

#[no_mangle]
pub unsafe extern "C" fn nq_dtype_array(inner: *const DataType, width: usize) -> *mut DataType {
    boxed(guard(|| Ok(DataType::Array(Box::new(borrow(inner, "dtype")?.clone()), width))))
}

#[no_mangle]
pub unsafe extern "C" fn nq_dtype_struct(
    names_: *const *const c_char,
    dtypes: *const *const DataType,
    n: usize,
) -> *mut DataType {
    boxed(guard(|| {
        let ns = names(names_, n)?;
        let ds = slice(dtypes, n)?;
        let mut fields = Vec::with_capacity(n);
        for (name, d) in ns.iter().zip(ds) {
            fields.push(Field::new((*name).into(), borrow(*d, "dtype")?.clone()));
        }
        Ok(DataType::Struct(fields))
    }))
}

/// Kind code (`NqDtype`) of a data type, or -1 on error.
#[no_mangle]
pub unsafe extern "C" fn nq_dtype_kind(d: *const DataType) -> i32 {
    guard(|| Ok(dtype_code(borrow(d, "dtype")?) as i32)).unwrap_or(-1)
}

/// Polars' name of a data type (`list[i64]`). Free with `nq_string_free`.
#[no_mangle]
pub unsafe extern "C" fn nq_dtype_name(d: *const DataType) -> *mut c_char {
    guard(|| Ok(to_c_string(borrow(d, "dtype")?.to_string()))).unwrap_or(ptr::null_mut())
}

/// Time unit code of a Datetime or Duration, or -1.
#[no_mangle]
pub unsafe extern "C" fn nq_dtype_time_unit(d: *const DataType) -> i32 {
    guard(|| match borrow(d, "dtype")? {
        DataType::Datetime(u, _) | DataType::Duration(u) => Ok(time_unit_code(u) as i32),
        other => Err(format!("{other} has no time unit")),
    })
    .unwrap_or(-1)
}

/// Time zone of a Datetime ("" for none). Free with `nq_string_free`.
#[no_mangle]
pub unsafe extern "C" fn nq_dtype_time_zone(d: *const DataType) -> *mut c_char {
    guard(|| match borrow(d, "dtype")? {
        DataType::Datetime(_, tz) => Ok(to_c_string(tz.as_ref().map(|t| t.to_string()).unwrap_or_default())),
        _ => Ok(to_c_string(String::new())),
    })
    .unwrap_or(ptr::null_mut())
}

fn enum_categories(d: &DataType) -> Result<Vec<String>, String> {
    match d {
        DataType::Enum(fc, _) => Ok(fc.categories().values_iter().map(|s| s.to_string()).collect()),
        other => Err(format!("{other} is not an Enum")),
    }
}

/// Number of categories of an Enum, or -1.
#[no_mangle]
pub unsafe extern "C" fn nq_dtype_n_categories(d: *const DataType) -> i64 {
    guard(|| Ok(enum_categories(borrow(d, "dtype")?)?.len() as i64)).unwrap_or(-1)
}

/// Category `i` of an Enum. Free with `nq_string_free`.
#[no_mangle]
pub unsafe extern "C" fn nq_dtype_category(d: *const DataType, i: usize) -> *mut c_char {
    guard(|| {
        let cats = enum_categories(borrow(d, "dtype")?)?;
        cats.get(i).cloned().map(to_c_string).ok_or_else(|| format!("no category {i}"))
    })
    .unwrap_or(ptr::null_mut())
}

/// Element type of a List or Array, as a new handle.
#[no_mangle]
pub unsafe extern "C" fn nq_dtype_inner(d: *const DataType) -> *mut DataType {
    boxed(guard(|| match borrow(d, "dtype")? {
        DataType::List(inner) | DataType::Array(inner, _) => Ok((**inner).clone()),
        other => Err(format!("{other} has no inner type")),
    }))
}

/// Width of an Array, or -1.
#[no_mangle]
pub unsafe extern "C" fn nq_dtype_width(d: *const DataType) -> i64 {
    guard(|| match borrow(d, "dtype")? {
        DataType::Array(_, w) => Ok(*w as i64),
        other => Err(format!("{other} is not an Array")),
    })
    .unwrap_or(-1)
}

fn struct_fields(d: &DataType) -> Result<&Vec<Field>, String> {
    match d {
        DataType::Struct(fs) => Ok(fs),
        other => Err(format!("{other} is not a Struct")),
    }
}

/// Number of fields of a Struct, or -1.
#[no_mangle]
pub unsafe extern "C" fn nq_dtype_n_fields(d: *const DataType) -> i64 {
    guard(|| Ok(struct_fields(borrow(d, "dtype")?)?.len() as i64)).unwrap_or(-1)
}

/// Name of field `i` of a Struct. Free with `nq_string_free`.
#[no_mangle]
pub unsafe extern "C" fn nq_dtype_field_name(d: *const DataType, i: usize) -> *mut c_char {
    guard(|| {
        let fs = struct_fields(borrow(d, "dtype")?)?;
        fs.get(i).map(|f| to_c_string(f.name().to_string())).ok_or_else(|| format!("no field {i}"))
    })
    .unwrap_or(ptr::null_mut())
}

/// Data type of field `i` of a Struct, as a new handle.
#[no_mangle]
pub unsafe extern "C" fn nq_dtype_field(d: *const DataType, i: usize) -> *mut DataType {
    boxed(guard(|| {
        let fs = struct_fields(borrow(d, "dtype")?)?;
        fs.get(i).map(|f| f.dtype().clone()).ok_or_else(|| format!("no field {i}"))
    }))
}

// ---------------------------------------------------------------------------
// Nested Series from their parts, and back (0.5)
// ---------------------------------------------------------------------------

unsafe fn validity<'a>(valid: *const bool, n: usize) -> Result<Option<&'a [bool]>, String> {
    if valid.is_null() { Ok(None) } else { Ok(Some(slice(valid, n)?)) }
}

/// A List Series of `n` rows: row i holds `inner[offsets[i] .. offsets[i+1]]`,
/// or null where `valid` (may be NULL) is false.
#[no_mangle]
pub unsafe extern "C" fn nq_series_list_from_parts(
    name: *const c_char,
    inner: *const Series,
    offsets: *const i64,
    valid: *const bool,
    n: usize,
) -> *mut Series {
    boxed(guard(|| {
        let inner = borrow(inner, "series")?;
        let offs = slice(offsets, n + 1)?;
        let valid = validity(valid, n)?;
        let mut b = polars::chunked_array::builder::get_list_builder(inner.dtype(), inner.len(), n, cstr(name)?.into());
        for i in 0..n {
            if valid.map(|v| v[i]).unwrap_or(true) {
                let (a, z) = (offs[i] as usize, offs[i + 1] as usize);
                b.append_series(&inner.slice(a as i64, z - a)).map_err(pe)?;
            } else {
                b.append_null();
            }
        }
        let s = b.finish().into_series();
        Ok(s)
    }))
}

/// A Struct Series from field Series of equal length, with null rows where
/// `valid` (may be NULL) is false.
#[no_mangle]
pub unsafe extern "C" fn nq_series_struct_from_fields(
    name: *const c_char,
    fields: *const *const Series,
    n_fields: usize,
    valid: *const bool,
    n: usize,
) -> *mut Series {
    boxed(guard(|| {
        let fs: Vec<Series> = slice(fields, n_fields)?
            .iter()
            .map(|f| borrow(*f, "series").cloned())
            .collect::<Result<_, _>>()?;
        let ca = StructChunked::from_series(cstr(name)?.into(), n, fs.iter()).map_err(pe)?;
        let ca = match validity(valid, n)? {
            Some(v) => ca.with_outer_validity(Some(v.iter().copied().collect())),
            None => ca,
        };
        Ok(ca.into_series())
    }))
}

/// Writes whether each of the `n` rows of `s` is not null.
#[no_mangle]
pub unsafe extern "C" fn nq_series_validity(s: *const Series, out: *mut bool, n: usize) -> bool {
    guard(|| {
        let s = borrow(s, "series")?;
        if s.len() != n {
            return Err(format!("series has {} rows, not {n}", s.len()));
        }
        let out = std::slice::from_raw_parts_mut(out, n);
        let nn = s.is_not_null();
        for (o, v) in out.iter_mut().zip(nn.iter()) {
            *o = v.unwrap_or(false);
        }
        Ok(())
    })
    .is_some()
}

fn as_list(s: &Series) -> Result<ListChunked, String> {
    match s.dtype() {
        DataType::List(_) => Ok(s.list().map_err(pe)?.rechunk().into_owned()),
        DataType::Array(inner, _) => {
            let l = s.cast(&DataType::List(inner.clone())).map_err(pe)?;
            Ok(l.list().map_err(pe)?.rechunk().into_owned())
        }
        other => Err(format!("{other} is not a list or array")),
    }
}

/// Writes the `n + 1` offsets of a List (or Array) Series of `n` rows, from 0;
/// null rows are empty.
#[no_mangle]
pub unsafe extern "C" fn nq_series_list_offsets(s: *const Series, out: *mut i64, n: usize) -> bool {
    guard(|| {
        let ca = as_list(borrow(s, "series")?)?;
        if ca.len() != n {
            return Err(format!("series has {} rows, not {n}", ca.len()));
        }
        let out = std::slice::from_raw_parts_mut(out, n + 1);
        out[0] = 0;
        if n > 0 {
            let offs = ca.downcast_as_array().offsets().as_slice();
            let base = offs[0];
            for i in 0..=n {
                out[i] = offs[i] - base;
            }
        }
        Ok(())
    })
    .is_some()
}

/// The values of all lists of a List (or Array) Series, one after the other.
#[no_mangle]
pub unsafe extern "C" fn nq_series_inner(s: *const Series) -> *mut Series {
    boxed(guard(|| {
        let ca = as_list(borrow(s, "series")?)?;
        let inner = ca.get_inner();
        if ca.is_empty() {
            return Ok(inner.slice(0, 0));
        }
        let offs = ca.downcast_as_array().offsets().as_slice();
        let (a, z) = (offs[0] as usize, offs[offs.len() - 1] as usize);
        Ok(inner.slice(a as i64, z - a))
    }))
}

/// Number of fields of a Struct Series, or -1.
#[no_mangle]
pub unsafe extern "C" fn nq_series_n_fields(s: *const Series) -> i64 {
    guard(|| Ok(borrow(s, "series")?.struct_().map_err(pe)?.struct_fields().len() as i64)).unwrap_or(-1)
}

/// Field `i` of a Struct Series (values of null rows are unspecified).
#[no_mangle]
pub unsafe extern "C" fn nq_series_struct_field(s: *const Series, i: usize) -> *mut Series {
    boxed(guard(|| {
        let fs = borrow(s, "series")?.struct_().map_err(pe)?.fields_as_series();
        fs.get(i).cloned().ok_or_else(|| format!("no field {i}"))
    }))
}

// ---------------------------------------------------------------------------
// 0.5: the list namespace, explode, implode (add-list-namespace)
// ---------------------------------------------------------------------------

/// List functions. Keep in sync with `NqListOp` in nanuq/ffi.nim.
#[repr(C)]
#[derive(Clone, Copy)]
pub enum NqListOp {
    Len = 0,
    Sum,
    Min,
    Max,
    Mean,
    Median,
    Std,
    Var,
    First,
    Last,
    ArgMin,
    ArgMax,
    NUnique,
    Any,
    All,
    Get,
    Gather,
    GatherEvery,
    Slice,
    Head,
    Tail,
    Contains,
    CountMatches,
    Join,
    Sort,
    Reverse,
    Unique,
    DropNulls,
    Diff,
    Shift,
    SampleN,
    SampleFraction,
    Filter,
    Union,
    SetDifference,
    SetIntersection,
    SetSymmetricDifference,
    ToArray,
    ToStruct,
    Eval,
    Agg,
    Explode,
}

/// One entry point for the `list` namespace. `a` and `b` are expression
/// arguments (NULL: a null literal), `f1`..`f3` boolean options, `n` a count
/// (ddof, width, diff periods) and `names`/`n_names` the `to_struct` fields.
#[no_mangle]
pub unsafe extern "C" fn nq_expr_list(
    e: *const Expr,
    op: NqListOp,
    a: *const Expr,
    b: *const Expr,
    f1: bool,
    f2: bool,
    f3: bool,
    n: i64,
    seed: i64,
    names_: *const *const c_char,
    n_names: usize,
) -> *mut Expr {
    boxed(guard(|| {
        let ex = borrow(e, "expression")?.clone();
        let ns = ex.clone().list();
        let a = opt_expr(a)?;
        let b = opt_expr(b)?;
        let seed = (seed >= 0).then_some(seed as u64);
        Ok(match op {
            NqListOp::Len => ns.len(),
            NqListOp::Sum => ns.sum(),
            NqListOp::Min => ns.min(),
            NqListOp::Max => ns.max(),
            NqListOp::Mean => ns.mean(),
            NqListOp::Median => ns.median(),
            NqListOp::Std => ns.std(n as u8),
            NqListOp::Var => ns.var(n as u8),
            NqListOp::First => ns.first(),
            NqListOp::Last => ns.last(),
            NqListOp::ArgMin => ns.arg_min(),
            NqListOp::ArgMax => ns.arg_max(),
            NqListOp::NUnique => ns.agg(element().n_unique()),
            NqListOp::Any => ns.agg(element().any(true)),
            NqListOp::All => ns.agg(element().all(true)),
            NqListOp::Get => ns.get(a, f1),
            NqListOp::Gather => ns.gather(a, f1),
            NqListOp::GatherEvery => ns.gather_every(a, b),
            NqListOp::Slice => ns.slice(a, b),
            NqListOp::Head => ns.head(a),
            NqListOp::Tail => ns.tail(a),
            NqListOp::Contains => ns.contains(a, f1),
            NqListOp::CountMatches => ns.count_matches(a),
            NqListOp::Join => ns.join(a, f1),
            NqListOp::Sort => ns.sort(
                SortOptions::default().with_order_descending(f1).with_nulls_last(f2).with_maintain_order(f3),
            ),
            NqListOp::Reverse => ns.eval(element().reverse()),
            NqListOp::Unique => if f1 { ns.eval(element().unique_stable()) } else { ns.eval(element().unique()) },
            NqListOp::DropNulls => ns.drop_nulls(),
            NqListOp::Diff => {
                let nb = if f1 { polars_core::series::ops::NullBehavior::Drop } else { polars_core::series::ops::NullBehavior::Ignore };
                ns.diff(n, nb)
            }
            NqListOp::Shift => ns.shift(a),
            NqListOp::SampleN => ns.sample_n(a, f1, Some(f2), seed),
            NqListOp::SampleFraction => ns.sample_fraction(a, f1, Some(f2), seed),
            NqListOp::Filter => ns.eval(element().filter(a)),
            NqListOp::Union => ns.union(a),
            NqListOp::SetDifference => ns.set_difference(a),
            NqListOp::SetIntersection => ns.set_intersection(a),
            NqListOp::SetSymmetricDifference => ns.set_symmetric_difference(a),
            NqListOp::ToArray => ns.to_array(n as usize),
            NqListOp::ToStruct => {
                let fs: Vec<PlSmallStr> = names(names_, n_names)?.into_iter().map(PlSmallStr::from).collect();
                ns.to_struct(fs.into())
            }
            NqListOp::Eval => ns.eval(a),
            NqListOp::Agg => ns.agg(a),
            NqListOp::Explode => ex.explode(ExplodeOptions { empty_as_null: f1, keep_nulls: f2 }),
        })
    }))
}

#[no_mangle]
pub unsafe extern "C" fn nq_expr_implode(e: *const Expr) -> *mut Expr {
    boxed(guard(|| Ok(borrow(e, "expression")?.clone().implode(true))))
}

#[no_mangle]
pub unsafe extern "C" fn nq_concat_list(es: *const *const Expr, n: usize) -> *mut Expr {
    boxed(guard(|| {
        let es: Vec<Expr> = slice(es, n)?.iter().map(|e| borrow(*e, "expression").cloned()).collect::<Result<_, _>>()?;
        concat_list(es).map_err(pe)
    }))
}

/// One row per value of the list columns `names_` (which must have lists of
/// equal lengths in each row).
#[no_mangle]
pub unsafe extern "C" fn nq_lf_explode(
    lf_: *const LazyFrame,
    names_: *const *const c_char,
    n: usize,
    empty_as_null: bool,
    keep_nulls: bool,
) -> *mut LazyFrame {
    boxed(guard(|| {
        let ns = names(names_, n)?;
        Ok(lf(lf_)?.explode(cols(ns), ExplodeOptions { empty_as_null, keep_nulls }))
    }))
}

// ---------------------------------------------------------------------------
// 0.5: string functions that give lists and structs (add-nested-strings)
// ---------------------------------------------------------------------------

/// Keep in sync with `NqStrNestedOp` in nanuq/ffi.nim.
#[repr(C)]
#[derive(Clone, Copy)]
pub enum NqStrNestedOp {
    Split = 0,
    SplitExact,
    SplitN,
    ExtractAll,
    ExtractGroups,
    ContainsAny,
    ReplaceMany,
    ExtractMany,
    FindMany,
    JsonDecode,
    JsonPathMatch,
}

/// `a`, `b`: expression arguments (by, patterns, replacements, path); `f1`,
/// `f2`: inclusive / ascii_case_insensitive, overlapping; `n` a count; `pat`
/// the extract_groups regex; `spec` the json_decode dtype.
#[no_mangle]
pub unsafe extern "C" fn nq_expr_str_nested(
    e: *const Expr,
    op: NqStrNestedOp,
    a: *const Expr,
    b: *const Expr,
    f1: bool,
    f2: bool,
    f3: bool,
    n: usize,
    pat: *const c_char,
    spec: *const NqDtypeSpec,
) -> *mut Expr {
    boxed(guard(|| {
        let ns = borrow(e, "expression")?.clone().str();
        let a = opt_expr(a)?;
        let b = opt_expr(b)?;
        Ok(match op {
            NqStrNestedOp::Split => if f1 { ns.split_inclusive(a) } else { ns.split(a) },
            NqStrNestedOp::SplitExact => if f1 { ns.split_exact_inclusive(a, n) } else { ns.split_exact(a, n) },
            NqStrNestedOp::SplitN => ns.splitn(a, n),
            NqStrNestedOp::ExtractAll => ns.extract_all(a),
            NqStrNestedOp::ExtractGroups => ns.extract_groups(cstr(pat)?).map_err(pe)?,
            NqStrNestedOp::ContainsAny => ns.contains_any(a, f1),
            NqStrNestedOp::ReplaceMany => ns.replace_many(a, b, f1, f3),
            NqStrNestedOp::ExtractMany => ns.extract_many(a, f1, f2, f3),
            NqStrNestedOp::FindMany => ns.find_many(a, f1, f2, f3),
            NqStrNestedOp::JsonDecode => ns.json_decode(dtype_from_spec(borrow(spec, "dtype")?)?),
            NqStrNestedOp::JsonPathMatch => ns.json_path_match(a),
        })
    }))
}

// ---------------------------------------------------------------------------
// 0.5: structs, unnest, value_counts and the arr namespace (add-struct-namespace)
// ---------------------------------------------------------------------------

unsafe fn exprs_of(es: *const *const Expr, n: usize) -> Result<Vec<Expr>, String> {
    slice(es, n)?.iter().map(|e| borrow(*e, "expression").cloned()).collect()
}

#[no_mangle]
pub unsafe extern "C" fn nq_as_struct(es: *const *const Expr, n: usize) -> *mut Expr {
    boxed(guard(|| Ok(as_struct(exprs_of(es, n)?))))
}

/// Keep in sync with `NqStructOp` in nanuq/ffi.nim.
#[repr(C)]
#[derive(Clone, Copy)]
pub enum NqStructOp {
    FieldByName = 0,
    FieldByNames,
    FieldByIndex,
    RenameFields,
    WithFields,
    JsonEncode,
}

#[no_mangle]
pub unsafe extern "C" fn nq_expr_struct(
    e: *const Expr,
    op: NqStructOp,
    names_: *const *const c_char,
    n_names: usize,
    es: *const *const Expr,
    n_es: usize,
    index: i64,
) -> *mut Expr {
    boxed(guard(|| {
        let ns = borrow(e, "expression")?.clone().struct_();
        let ns_ = names(names_, n_names)?;
        Ok(match op {
            NqStructOp::FieldByName => ns.field_by_name(ns_.first().ok_or("no field name")?),
            NqStructOp::FieldByNames => ns.field_by_names(ns_.iter().map(|s| PlSmallStr::from(*s))),
            NqStructOp::FieldByIndex => ns.field_by_index(index),
            NqStructOp::RenameFields => ns.rename_fields(ns_.iter().map(|s| PlSmallStr::from(*s))),
            NqStructOp::WithFields => ns.with_fields(exprs_of(es, n_es)?),
            NqStructOp::JsonEncode => ns.json_encode(),
        })
    }))
}

#[no_mangle]
pub unsafe extern "C" fn nq_expr_value_counts(
    e: *const Expr,
    sort: bool,
    parallel: bool,
    name: *const c_char,
    normalize: bool,
) -> *mut Expr {
    boxed(guard(|| {
        let name = cstr(name)?;
        let name = if name.is_empty() { if normalize { "proportion" } else { "count" } } else { name };
        Ok(borrow(e, "expression")?.clone().value_counts(sort, parallel, name, normalize))
    }))
}

#[no_mangle]
pub unsafe extern "C" fn nq_lf_unnest(
    lf_: *const LazyFrame,
    names_: *const *const c_char,
    n: usize,
    separator: *const c_char,
) -> *mut LazyFrame {
    boxed(guard(|| {
        let ns = names(names_, n)?;
        let sep = if separator.is_null() { None } else { Some(PlSmallStr::from(cstr(separator)?)) };
        Ok(lf(lf_)?.unnest(cols(ns), sep))
    }))
}

/// Keep in sync with `NqArrOp` in nanuq/ffi.nim.
#[repr(C)]
#[derive(Clone, Copy)]
pub enum NqArrOp {
    Len = 0,
    Sum,
    Min,
    Max,
    Mean,
    Median,
    Std,
    Var,
    ArgMin,
    ArgMax,
    Get,
    Join,
    Contains,
    CountMatches,
    Sort,
    Slice,
    Head,
    Tail,
    Shift,
    ToList,
    ToStruct,
    Explode,
    Eval,
    Agg,
}

#[no_mangle]
pub unsafe extern "C" fn nq_expr_arr(
    e: *const Expr,
    op: NqArrOp,
    a: *const Expr,
    b: *const Expr,
    f1: bool,
    f2: bool,
    n: i64,
) -> *mut Expr {
    boxed(guard(|| {
        let ns = borrow(e, "expression")?.clone().arr();
        let a = opt_expr(a)?;
        let b = opt_expr(b)?;
        Ok(match op {
            NqArrOp::Len => ns.len(),
            NqArrOp::Sum => ns.sum(),
            NqArrOp::Min => ns.min(),
            NqArrOp::Max => ns.max(),
            NqArrOp::Mean => ns.mean(),
            NqArrOp::Median => ns.median(),
            NqArrOp::Std => ns.std(n as u8),
            NqArrOp::Var => ns.var(n as u8),
            NqArrOp::ArgMin => ns.arg_min(),
            NqArrOp::ArgMax => ns.arg_max(),
            NqArrOp::Get => ns.get(a, f1),
            NqArrOp::Join => ns.join(a, f1),
            NqArrOp::Contains => ns.contains(a, f1),
            NqArrOp::CountMatches => ns.count_matches(a),
            NqArrOp::Sort => ns.sort(SortOptions::default().with_order_descending(f1).with_nulls_last(f2)),
            NqArrOp::Slice => ns.slice(a, b, f1).map_err(pe)?,
            NqArrOp::Head => ns.head(a, f1).map_err(pe)?,
            NqArrOp::Tail => ns.tail(a, f1).map_err(pe)?,
            NqArrOp::Shift => ns.shift(a),
            NqArrOp::ToList => ns.to_list(),
            NqArrOp::ToStruct => ns.to_struct(None),
            NqArrOp::Explode => ns.explode(ExplodeOptions { empty_as_null: f1, keep_nulls: f2 }),
            NqArrOp::Eval => ns.eval(a, f1),
            NqArrOp::Agg => ns.agg(a),
        })
    }))
}

// ---------------------------------------------------------------------------
// 0.5: JSON and NDJSON (add-json-io)
// ---------------------------------------------------------------------------

unsafe fn schema_of(
    names_: *const *const c_char,
    specs: *const NqDtypeSpec,
    n: usize,
) -> Result<Option<SchemaRef>, String> {
    if n == 0 {
        return Ok(None);
    }
    let ns = names(names_, n)?;
    let ds = dtypes_from_specs(specs, n)?;
    Ok(Some(Arc::new(Schema::from_iter(
        ns.iter().zip(ds).map(|(n, d)| Field::new((*n).into(), d)),
    ))))
}

/// Reads JSON (an array of objects, or with `lines` NDJSON) from `path`, or
/// from `data_len` bytes at `data` when `data` is not NULL. `full_schema`
/// says whether the named dtypes are the whole schema or overrides.
#[no_mangle]
pub unsafe extern "C" fn nq_df_read_json(
    path: *const c_char,
    data: *const u8,
    data_len: usize,
    lines: bool,
    names_: *const *const c_char,
    specs: *const NqDtypeSpec,
    n: usize,
    full_schema: bool,
    infer_schema_length: i64,
    ignore_errors: bool,
) -> *mut DataFrame {
    boxed(guard(|| {
        let bytes: Vec<u8> = if data.is_null() {
            std::fs::read(cstr(path)?).map_err(ioe)?
        } else {
            std::slice::from_raw_parts(data, data_len).to_vec()
        };
        let schema = schema_of(names_, specs, n)?;
        let fmt = if lines { JsonFormat::JsonLines } else { JsonFormat::Json };
        let infer = if infer_schema_length < 0 {
            None
        } else {
            std::num::NonZeroUsize::new(infer_schema_length as usize)
        };
        let mut r = JsonReader::new(std::io::Cursor::new(bytes))
            .with_json_format(fmt)
            .infer_schema_len(infer)
            .with_ignore_errors(ignore_errors);
        let ov;
        match (&schema, full_schema) {
            (Some(s), true) => r = r.with_schema(s.clone()),
            (Some(s), false) => {
                ov = s.clone();
                r = r.with_schema_overwrite(&ov);
                return r.finish().map_err(pe);
            }
            _ => {}
        }
        r.finish().map_err(pe)
    }))
}

#[no_mangle]
pub unsafe extern "C" fn nq_lf_scan_ndjson(
    path: *const c_char,
    data: *const u8,
    data_len: usize,
    n_rows: i64,
    row_index_name: *const c_char,
    row_index_offset: u32,
    names_: *const *const c_char,
    specs: *const NqDtypeSpec,
    n: usize,
    full_schema: bool,
    infer_schema_length: i64,
    ignore_errors: bool,
) -> *mut LazyFrame {
    boxed(guard(|| {
        let sources = scan_sources(path, data, data_len)?;
        let schema = schema_of(names_, specs, n)?;
        let infer = if infer_schema_length < 0 {
            None
        } else {
            std::num::NonZeroUsize::new(infer_schema_length as usize)
        };
        let mut r = LazyJsonLineReader::new_with_sources(sources)
            .with_n_rows((n_rows >= 0).then_some(n_rows as usize))
            .with_row_index(row_index(row_index_name, row_index_offset)?)
            .with_infer_schema_length(infer)
            .with_ignore_errors(ignore_errors);
        r = if full_schema { r.with_schema(schema) } else { r.with_schema_overwrite(schema) };
        r.finish().map_err(pe)
    }))
}

/// Writes `df` as JSON (with `lines`, NDJSON) to `path`, or, when `path` is
/// NULL, returns the text (free with `nq_string_free`). Returns "" after
/// writing a file, NULL on error.
#[no_mangle]
pub unsafe extern "C" fn nq_df_write_json(df: *const DataFrame, path: *const c_char, lines: bool) -> *mut c_char {
    guard(|| {
        let mut df = borrow(df, "DataFrame")?.clone();
        let fmt = if lines { JsonFormat::JsonLines } else { JsonFormat::Json };
        if path.is_null() {
            let mut buf: Vec<u8> = Vec::new();
            JsonWriter::new(&mut buf).with_json_format(fmt).finish(&mut df).map_err(pe)?;
            Ok(to_c_string(String::from_utf8(buf).map_err(|e| e.to_string())?))
        } else {
            let file = File::create(cstr(path)?).map_err(ioe)?;
            JsonWriter::new(file).with_json_format(fmt).finish(&mut df).map_err(pe)?;
            Ok(to_c_string(String::new()))
        }
    })
    .unwrap_or(ptr::null_mut())
}
