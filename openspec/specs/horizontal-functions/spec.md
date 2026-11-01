# horizontal-functions Specification

## Purpose
Functions that compute across the columns of a row, columns generated from ranges and repeated values, and correlation between columns.

## Requirements

### Requirement: Horizontal functions
`sumHorizontal`, `meanHorizontal`, `minHorizontal`, `maxHorizontal`, `allHorizontal`,
`anyHorizontal` and `coalesce` SHALL compute row by row over their arguments, which
SHALL be expressions, literals, selectors (expanded to their columns) or a list of
column names. `sumHorizontal` and `meanHorizontal` SHALL skip nulls unless
`ignoreNulls = false`, and `coalesce` SHALL return the first non-null value.

```nim
let df = newDataFrame:
  station: ["Lima", "Piura", "Tumbes"]
  jan: [1.0, 4.0, nil]
  feb: [2.0, 30.0, 61.0]
  mar: [1.0, 80.0, 95.0]
echo df.select(col.station, sumHorizontal(col(float)).alias("total"),
               maxHorizontal("jan", "feb", "mar").alias("wettest"),
               coalesce(col.jan, col.feb).alias("first_reading"))
```

```text
shape: (3, 4)
┌─────────┬───────┬─────────┬───────────────┐
│ station ┆ total ┆ wettest ┆ first_reading │
│ ---     ┆ ---   ┆ ---     ┆ ---           │
│ str     ┆ f64   ┆ str     ┆ f64           │
╞═════════╪═══════╪═════════╪═══════════════╡
│ Lima    ┆ 4.0   ┆ mar     ┆ 1.0           │
│ Piura   ┆ 114.0 ┆ mar     ┆ 4.0           │
│ Tumbes  ┆ 156.0 ┆ mar     ┆ 61.0          │
└─────────┴───────┴─────────┴───────────────┘
```

#### Scenario: Nulls in a sum
- **WHEN** `sumHorizontal([col.a, col.b], ignoreNulls = false)` runs on a row where `b` is null
- **THEN** that row's sum is null

#### Scenario: All and any
- **WHEN** `allHorizontal` and `anyHorizontal` run on a row holding true and false
- **THEN** they give false and true

### Requirement: Generated columns
`intRange(start, stop, step = 1, dtype = Int64)` (or `intRange(stop)`) SHALL produce the
integers from `start` up to `stop` excluded, `linearSpace(start, stop, numSamples,
closed)` SHALL produce evenly spaced floats, and `repeat(value, n)` SHALL repeat a value
`n` times. A string value SHALL be wrapped in `lit`, since std/strutils' `repeat`
takes plain strings.

```nim
echo newDataFrame().select(intRange(1950, 2026, 25).alias("year"),
                           linearSpace(0, 1, 4).alias("share"),
                           repeat(lit("ENSO"), 4).alias("index"))
```

```text
shape: (4, 3)
┌──────┬──────────┬───────┐
│ year ┆ share    ┆ index │
│ ---  ┆ ---      ┆ ---   │
│ i64  ┆ f64      ┆ str   │
╞══════╪══════════╪═══════╡
│ 1950 ┆ 0.0      ┆ ENSO  │
│ 1975 ┆ 0.333333 ┆ ENSO  │
│ 2000 ┆ 0.666667 ┆ ENSO  │
│ 2025 ┆ 1.0      ┆ ENSO  │
└──────┴──────────┴───────┘
```

#### Scenario: Zero step
- **WHEN** `intRange(0, 5, step = 0)` is built
- **THEN** `ValueError` is raised

### Requirement: Correlation
`corr(a, b, correlationMethod = Pearson)` SHALL return the Pearson or Spearman
correlation of two columns as an aggregation, and `cov(a, b, ddof = 1)` their covariance.

```nim
let df = newDataFrame:
  oni: [-1.0, 0.0, 0.5, 2.0]
  world: [14.6, 14.8, 14.9, 15.2]
echo df.select(corr("oni", "world").round(3).alias("pearson"),
               corr("oni", "world", Spearman).alias("spearman"))
```

```text
shape: (1, 2)
┌─────────┬──────────┐
│ pearson ┆ spearman │
│ ---     ┆ ---      │
│ f64     ┆ f64      │
╞═════════╪══════════╡
│ 1.0     ┆ 1.0      │
└─────────┴──────────┘
```

#### Scenario: Perfect correlation
- **WHEN** `corr` runs on 1, 2, 3 and 2, 4, 6
- **THEN** the result is 1.0
