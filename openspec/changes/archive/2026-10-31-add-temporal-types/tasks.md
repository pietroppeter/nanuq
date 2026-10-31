# Tasks

## 1. Bridge

- [x] 1.1 Add `NqDtypeSpec` and use it for casts, selectors and schema overrides
- [x] 1.2 Add temporal series, literals, `nq_expr_to_physical`, time unit and zone getters
- [x] 1.3 Add `nq_expr_date_range`, `nq_expr_duration`, `nq_expr_strptime` and `nq_expr_dt` with `NqDtOp`; mirror everything in `ffi.nim`

## 2. Nim API

- [x] 2.1 Add the temporal `DataTypeKind`s, `timeUnit`/`timeZone`, `Date`, `TimeOfDay` and the conversions
- [x] 2.2 Accept temporal values in `series`, block `newDataFrame`, `lit`, `toList`, `[]`, `fillNull` and casts
- [x] 2.3 Add `dateRange`, `datetimeRange`, `duration`, `toPolarsInterval` and the parsing procs; `tryParseDates`
- [x] 2.4 Add `DtNameSpace` and every function listed in the proposal; temporal `glimpse` and `describe`
- [x] 2.5 Write `tests/test_temporal.nim`; add it to `nanuq.nimble` and `.gitignore`

## 3. Docs and integration

- [x] 3.1 README lists temporal types; `nimble test` and `nimble specexamples` pass
- [x] 3.2 Archive the change: update BACKLOG "More dtypes", add CHANGELOG lines
