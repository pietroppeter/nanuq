# Tasks

## 1. Bridge

- [x] 1.1 Add the Categorical and Enum dtype codes and Enum categories in `NqDtypeSpec`
- [x] 1.2 Add `nq_df_column_n_categories`, `nq_df_column_category`, `nq_series_cast` and `nq_expr_cat`; mirror them in `ffi.nim`

## 2. Nim API

- [x] 2.1 Add the kinds, `categories`, `Categorical` and `Enum(...)`; Nim enums in `dataType`
- [x] 2.2 Accept Nim enums in `series`, block `newDataFrame`, `toList`, `[]`, comparisons and `isIn`
- [x] 2.3 Add `CatNameSpace`, `toPhysical`; no min/max in `describe`
- [x] 2.4 Write `tests/test_categorical.nim`; add it to `nanuq.nimble` and `.gitignore`

## 3. Docs and integration

- [x] 3.1 README lists categoricals; `nimble test` and `nimble specexamples` pass
- [x] 3.2 Archive the change: update BACKLOG "More dtypes", add CHANGELOG lines
