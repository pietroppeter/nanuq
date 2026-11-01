# cumulative-functions Specification

## Purpose
Functions that compare each row with the rows before it: shifting, differences, relative change, running totals and records, run ids and peaks.

## Requirements

### Requirement: Shifting
`e.shift(n = 1)` SHALL move values down by `n` rows (up when `n` is negative), filling
the rows left empty with null, or with `fillValue` when it is given. Inside `over`, the
shift SHALL happen within each group.

```nim
let df = newDataFrame:
  month: ["Jan", "Feb", "Mar", "Apr"]
  anomaly: [0.5, 0.8, 1.2, 0.9]
echo df.withColumns(col.anomaly.shift.alias("before"),
                    col.anomaly.shift(-1, fillValue = 0.0).alias("after"))
```

```text
shape: (4, 4)
┌───────┬─────────┬────────┬───────┐
│ month ┆ anomaly ┆ before ┆ after │
│ ---   ┆ ---     ┆ ---    ┆ ---   │
│ str   ┆ f64     ┆ f64    ┆ f64   │
╞═══════╪═════════╪════════╪═══════╡
│ Jan   ┆ 0.5     ┆ null   ┆ 0.8   │
│ Feb   ┆ 0.8     ┆ 0.5    ┆ 1.2   │
│ Mar   ┆ 1.2     ┆ 0.8    ┆ 0.9   │
│ Apr   ┆ 0.9     ┆ 1.2    ┆ 0.0   │
└───────┴─────────┴────────┴───────┘
```

#### Scenario: Shift within groups
- **WHEN** `col.x.shift.over(col.g)` runs on groups a = 1, 2 and b = 3, 4
- **THEN** the result is null, 1, null, 3

### Requirement: Differences
`e.diff(n = 1, nullBehavior = NullBehavior.Ignore)` SHALL subtract from each value the
value `n` rows above, with null where there is none; `NullBehavior.Drop` SHALL leave out
those rows. `e.pctChange(n = 1)` SHALL return the relative change from the value `n`
rows above.

```nim
let df = newDataFrame:
  year: [2021, 2022, 2023, 2024]
  temp: [14.8, 14.9, 15.1, 15.3]
echo df.select(col.year, col.temp.diff.round(2).alias("diff"),
               col.temp.pctChange.round(4).alias("pct"))
```

```text
shape: (4, 3)
┌──────┬──────┬────────┐
│ year ┆ diff ┆ pct    │
│ ---  ┆ ---  ┆ ---    │
│ i64  ┆ f64  ┆ f64    │
╞══════╪══════╪════════╡
│ 2021 ┆ null ┆ null   │
│ 2022 ┆ 0.1  ┆ 0.0068 │
│ 2023 ┆ 0.2  ┆ 0.0134 │
│ 2024 ┆ 0.2  ┆ 0.0132 │
└──────┴──────┴────────┘
```

#### Scenario: Drop the first row
- **WHEN** `diff(nullBehavior = Drop)` runs on 1, 4, 9
- **THEN** the result is 3, 5

### Requirement: Cumulative functions
`cumSum`, `cumProd`, `cumMin`, `cumMax` and `cumCount` SHALL return the running sum,
product, minimum, maximum and count of non-null values from the first row, or from the
last row with `reverse = true`.

```nim
let df = newDataFrame:
  rain: [3, 0, 7, 2]
echo df.withColumns(col.rain.cumSum.alias("total"), col.rain.cumMax.alias("wettest"),
                    col.rain.cumSum(reverse = true).alias("still_to_come"))
```

```text
shape: (4, 4)
┌──────┬───────┬─────────┬───────────────┐
│ rain ┆ total ┆ wettest ┆ still_to_come │
│ ---  ┆ ---   ┆ ---     ┆ ---           │
│ i64  ┆ i64   ┆ i64     ┆ i64           │
╞══════╪═══════╪═════════╪═══════════════╡
│ 3    ┆ 3     ┆ 3       ┆ 12            │
│ 0    ┆ 3     ┆ 3       ┆ 9             │
│ 7    ┆ 10    ┆ 7       ┆ 9             │
│ 2    ┆ 12    ┆ 7       ┆ 2             │
└──────┴───────┴─────────┴───────────────┘
```

#### Scenario: Running record
- **WHEN** `cumMax` runs on 3, 1, 5, 2
- **THEN** the result is 3, 3, 5, 5

#### Scenario: Count skips nulls
- **WHEN** `cumCount` runs on 1, null, 3
- **THEN** the result is 1, 1, 2

### Requirement: Runs and peaks
`e.rleId` SHALL number the runs of equal consecutive values, starting at 0 and growing by
one each time the value changes. `peakMax` and `peakMin` SHALL be true at local maxima
and minima.

```nim
let df = newDataFrame:
  season: ["DJF", "JFM", "FMA", "MAM", "AMJ", "MJJ"]
  warm: [true, true, false, false, true, true]
echo df.withColumns(col.warm.rleId.alias("run"))
```

```text
shape: (6, 3)
┌────────┬───────┬─────┐
│ season ┆ warm  ┆ run │
│ ---    ┆ ---   ┆ --- │
│ str    ┆ bool  ┆ u32 │
╞════════╪═══════╪═════╡
│ DJF    ┆ true  ┆ 0   │
│ JFM    ┆ true  ┆ 0   │
│ FMA    ┆ false ┆ 1   │
│ MAM    ┆ false ┆ 1   │
│ AMJ    ┆ true  ┆ 2   │
│ MJJ    ┆ true  ┆ 2   │
└────────┴───────┴─────┘
```

#### Scenario: Run lengths
- **WHEN** rows are grouped by `rleId` of true, true, false, true and counted
- **THEN** the runs have lengths 2, 1 and 1
