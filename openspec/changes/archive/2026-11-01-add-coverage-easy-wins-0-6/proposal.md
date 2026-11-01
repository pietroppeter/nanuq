# Proposal

## Why

The Polars coverage map (nanuq#60, `docs/coverage/polars.json`) lists the Python API
Nanuq still misses. Its thread picked out 30 items that each take hours, not days
(`/mnt/project-files/nanuq-0.6/easy-wins.md`), and Pietro asked for all three groups in
0.6 (2026-11-01): pure Nim helpers, small bridge calls on features already compiled
in, and items that turn on one more Polars feature.

It is the thirteenth change of the 0.6 release.

## What Changes

- **Pure Nim**: empty frames (`newDataFrame(schema = ...)`, `clear(n)`), `isEmpty`,
  `getColumnIndex`, `rowsByKey`, frame `shift` and `dropNans`, LazyFrame `shift`,
  `first`, `last`, `dt.epoch(unit)`, table formatting options (`setTblFormatting`,
  `setAsciiTables`, `setTblHide*`, `setTblCellAlignment`, ...), `bin` on Series.
- **Small bridge calls**: `eqMissing`, `neMissing`, `nth`, `cumulativeEval`,
  `roundSigFigs`, `dt.century`, `dt.millennium`, `dt.dstOffset`, `dt.baseUtcOffset`,
  `timeRange`, `timeRanges`, `str.escapeRegex`, `concatArr`, CSV `commentPrefix`,
  `scanParquet(hivePartitioning)`, `cache`, `QueryOptFlags` (`collect(optimizations)`,
  `withOptimizations`), `rechunk`, `shrinkToFit`, `nChunks`, `matchToSchema`, `readOds`.
- **One more Polars feature each**: `isClose` (is_close), `mergeSorted` (merge_sorted),
  `dt.addBusinessDays`, `dt.isBusinessDay`, `businessDayCount` (business),
  `str.normalize` (string_normalize), `reinterpret` (reinterpret), `readIpcStream` and
  `writeIpcStream` (ipc_streaming), and `cse` so that the common subplan and
  subexpression optimizations exist (py-polars has them on).

## Capabilities

### Modified Capabilities
- `frame-utilities`: empty frames, frame shortcuts, schema matching, merging sorted
  frames, query optimizations.
- `temporal`: more date parts, time ranges, business days.
- `expressions`: null-aware comparisons, closeness, `nth`, `cumulativeEval`,
  `roundSigFigs`, `reinterpret`, `concatArr`.
- `strings`: `escapeRegex`, `normalize`.
- `series`: the `bin` namespace on Series.
- `csv-io`: comment lines.
- `parquet-ipc`: Hive partitioning switch, IPC streams.
- `excel-io`: `readOds`.
- `inspection`: table formatting options.

## Differences from Polars

| Nanuq | Python | Rust (py-2.1.0) |
|---|---|---|
| `newDataFrame(schema = {...})` | `pl.DataFrame(schema=...)` | `DataFrame::empty_with_schema` |
| `clear(n)` | `clear(n)` | (Python only) |
| `isEmpty` | `is_empty` | `is_empty` |
| `getColumnIndex` | `get_column_index` | `get_column_index` |
| `rowsByKey(key, K, T, unique)` | `rows_by_key(key, named, include_key, unique)` | (Python only) |
| `shift`, `dropNans`, `first`, `last` on frames | same | `shift`, `drop_nans`, `first`, `last` |
| `dt.epoch(EpochUnit)` | `dt.epoch(time_unit)` | (Python only) |
| `setTblFormatting`, `setAsciiTables`, `setTblHide*`, ... | `Config.set_tbl_formatting`, ... | `POLARS_FMT_*` variables |
| `s.bin.*` | `Series.bin.*` | |
| `eqMissing`, `neMissing` | `eq_missing`, `ne_missing` | `eq_missing`, `neq_missing` |
| `nth(indices)` | `pl.nth(*indices)` | `dsl::nth` |
| `cumulativeEval(expr, minSamples)` | `cumulative_eval` | `cumulative_eval` |
| `roundSigFigs(digits)` | `round_sig_figs` | `round_sig_figs` |
| `dt.century`, `dt.millennium`, `dt.dstOffset`, `dt.baseUtcOffset` | same | same |
| `timeRange`, `timeRanges` | `pl.time_range(s)` | `time_range(s)` |
| `str.escapeRegex`, `str.normalize(UnicodeForm)` | `escape_regex`, `normalize` | same |
| `concatArr` | `pl.concat_arr` | `concat_arr` |
| `commentPrefix` | `comment_prefix` | `with_comment_prefix` |
| `hivePartitioning` | `hive_partitioning` | `HiveOptions` |
| `cache`, `QueryOptFlags`, `withOptimizations` | `cache`, `QueryOptFlags`, `collect(optimizations=)` | `cache`, `OptFlags` |
| `rechunk`, `shrinkToFit`, `nChunks` | `rechunk`, `shrink_to_fit`, `n_chunks` | `rechunk_mut`, `shrink_to_fit`, `max_n_chunks` |
| `matchToSchema` | `match_to_schema` | `match_to_schema` |
| `readOds` | `read_ods` | (calamine) |
| `isClose` | `is_close` | `is_close` |
| `mergeSorted(other, key)` | `merge_sorted` | `merge_sorted` |
| `dt.addBusinessDays`, `dt.isBusinessDay`, `businessDayCount` | same | same |
| `reinterpret(signed)` | `reinterpret(signed=)` | `reinterpret` |
| `readIpcStream`, `writeIpcStream` | `read_ipc_stream`, `write_ipc(..)`/`write_ipc_stream` | `IpcStreamReader`, `IpcStreamWriter` |

- `rowsByKey` returns an `OrderedTable` of Nim objects or tuples (`T`); the key column
  is in the rows only if `T` has a field for it (Python: `include_key`, `named`).
- `timeRange`/`timeRanges` need `start` and `stop` (Python defaults to the whole day).
- `matchToSchema` sets the same policy for every column and has no struct-field
  policies or fill expressions (Python takes a dict per column).
- `QueryOptFlags.none` keeps type coercion and checks on, as Python's; Python's
  deprecated `collect(predicate_pushdown=...)` keywords are not offered.
- Business days take `weekMask: array[7, bool]` and `holidays: openArray[Date]`, and
  `roll` is a `Roll` enum (Python strings).
- `nth` returns an expression, not a selector (it cannot be combined with `|`).
- Table options are switches (`setTblHideColumnNames(false)` turns it off again); the
  `withConfig` block takes the most used of them.

## Impact

- `src/rust/src/lib.rs`: `nq_expr_win`, `nq_expr_business_day_count`,
  `nq_expr_time_range`, `nq_expr_concat_arr`, `nq_expr_nth`, `nq_lf_with_optimizations`,
  `nq_lf_cache`, `nq_lf_drop_nans`, `nq_lf_merge_sorted`, `nq_lf_match_to_schema`,
  `nq_df_rechunk`, `nq_df_shrink_to_fit`, `nq_df_n_chunks`, IPC stream read/write, CSV
  `comment_prefix`, Parquet `hive`; features `is_close`, `merge_sorted`, `business`,
  `string_normalize`, `reinterpret`, `ipc_streaming`, `cse`.
- `src/nanuq.nim`, `src/nanuq/ffi.nim`; new `tests/test_easywins6.nim` and
  `tests/data/bears.ods`.
- `docs/coverage/polars.json`: these rows become covered.
