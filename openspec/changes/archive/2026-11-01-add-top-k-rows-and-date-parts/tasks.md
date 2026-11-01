## 1. Top k rows

- [x] 1.1 `nq_lf_top_k` (Rust `LazyFrame::top_k` / `bottom_k`)
- [x] 1.2 `topK`/`bottomK` for LazyFrame and DataFrame, `by` as names or expressions
- [x] 1.3 Tests

## 2. Dates from parts

- [x] 2.1 `nq_expr_date` (Rust `datetime(DatetimeArgs)` cast to Date)
- [x] 2.2 `date(year, month, day)` with expression parts
- [x] 2.3 Tests

## 3. Float precision

- [x] 3.1 `nq_set_float_precision` / `nq_get_float_precision`
- [x] 3.2 `setFloatPrecision`, `setConfig(floatPrecision)`, `withConfig`, `resetConfig`
- [x] 3.3 Tests

## 4. Specs for what already worked

- [x] 4.1 `groupBy` group order, `joinAsof(coalesce = false)`
