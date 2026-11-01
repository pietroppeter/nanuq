# frame-utilities Specification

## Purpose
Smaller expression and frame functions: sampling, hashing, meta, comparing, stacking, updating and upsampling.

## Requirements

### Requirement: Smaller expression functions
Expressions SHALL have `shuffle(seed)`, `sample(n or fraction)`, `hash(seed)`, `get(i)`,
`argTrue`, `upperBound`, `lowerBound`, `extendConstant(value, n)`, `rle` (a struct of
`len` and `value`) and `reshape(dims)`, and `over(partitionBy, mappingStrategy)` with
`MappingStrategy.GroupToRows`, `Join` or `Explode`.

```nim
let df = newDataFrame:
  den: ["A", "A", "B"]
  kg: [410, 380, 500]
echo df.select(col("kg").get(1).alias("second"), col("kg").upperBound.alias("max"))
echo df.select((col("kg") > 400).argTrue.alias("heavy"))
echo df.select(col("den"), col("kg").over("den", MappingStrategy.Join).alias("all"))
echo df.select(col("den").rle).unnest("den")
```

```text
shape: (1, 2)
┌────────┬─────────────────────┐
│ second ┆ max                 │
│ ---    ┆ ---                 │
│ i64    ┆ i64                 │
╞════════╪═════════════════════╡
│ 380    ┆ 9223372036854775807 │
└────────┴─────────────────────┘
shape: (2, 1)
┌───────┐
│ heavy │
│ ---   │
│ u32   │
╞═══════╡
│ 0     │
│ 2     │
└───────┘
shape: (3, 2)
┌─────┬────────────┐
│ den ┆ all        │
│ --- ┆ ---        │
│ str ┆ list[i64]  │
╞═════╪════════════╡
│ A   ┆ [410, 380] │
│ A   ┆ [410, 380] │
│ B   ┆ [500]      │
└─────┴────────────┘
shape: (2, 2)
┌─────┬───────┐
│ len ┆ value │
│ --- ┆ ---   │
│ u32 ┆ str   │
╞═════╪═══════╡
│ 2   ┆ A     │
│ 1   ┆ B     │
└─────┴───────┘
```

#### Scenario: Seeded shuffle
- **WHEN** `shuffle(seed = 1)` is evaluated twice
- **THEN** both results are the same permutation

### Requirement: Names and meta
`name.toLowercase` and `name.toUppercase` SHALL change output names, and `e.meta` SHALL
give `outputName`, `rootNames`, `hasMultipleOutputs`, `isColumn`, `isLiteral` and
`undoAliases`.

```nim
let e = (col("kg") * 2).alias("double")
echo e.meta.outputName, " ", e.meta.rootNames, " ", col("*").meta.hasMultipleOutputs
let df = newDataFrame:
  Bear: ["Ada"]
echo df.select(col("Bear").name.toUppercase).columns
```

```text
double @["kg"] true
@["BEAR"]
```

#### Scenario: No output name
- **WHEN** `outputName` is asked of `col("*")`
- **THEN** `ComputeError` is raised

### Requirement: Comparing and stacking frames
`a.equals(b, nullEqual = true)` SHALL tell whether two frames (or Series) have the same
names, types and values; `vstack` and `extend` SHALL append the rows of a frame with the
same schema, and `hstack` SHALL add Series or the columns of another frame.

```nim
let a = newDataFrame:
  bear: ["Ada"]
  kg: [410]
let b = newDataFrame:
  bear: ["Bo"]
  kg: [380]
echo a.vstack(b).hstack([series("den", ["A", "B"])])
echo a.equals(a), " ", a.equals(b)
```

```text
shape: (2, 3)
┌──────┬─────┬─────┐
│ bear ┆ kg  ┆ den │
│ ---  ┆ --- ┆ --- │
│ str  ┆ i64 ┆ str │
╞══════╪═════╪═════╡
│ Ada  ┆ 410 ┆ A   │
│ Bo   ┆ 380 ┆ B   │
└──────┴─────┴─────┘
true false
```

#### Scenario: Nulls
- **WHEN** two frames with a null in the same place are compared with `nullEqual = false`
- **THEN** `equals` is false

### Requirement: Updating, upsampling and partitions
`df.update(other, on, how)` SHALL replace values of `df` with the non-null values of
`other` in matching rows; `df.upsample(timeColumn, every, groupBy)` SHALL insert rows for
missing times at a regular interval; `estimatedSize` SHALL give the frame's size;
`partitionBy(by, asDict = true)` SHALL give a table from key values to frames; and
`collectAll(lfs)` SHALL collect several LazyFrames.

```nim
let df = newDataFrame:
  bear: ["Ada", "Bo"]
  kg: [410, 380]
let fix = newDataFrame:
  bear: ["Bo"]
  kg: [395]
echo df.update(fix, on = "bear")
let t = newDataFrame:
  day: [date(2026, 3, 1), date(2026, 3, 4)]
  seen: [3, 1]
echo t.upsample("day", every = "1d")
echo df.partitionBy("bear", asDict = true).len, " ", collectAll([df.lazy, fix.lazy]).len
```

```text
shape: (2, 2)
┌──────┬─────┐
│ bear ┆ kg  │
│ ---  ┆ --- │
│ str  ┆ i64 │
╞══════╪═════╡
│ Ada  ┆ 410 │
│ Bo   ┆ 395 │
└──────┴─────┘
shape: (4, 2)
┌────────────┬──────┐
│ day        ┆ seen │
│ ---        ┆ ---  │
│ date       ┆ i64  │
╞════════════╪══════╡
│ 2026-03-01 ┆ 3    │
│ 2026-03-02 ┆ null │
│ 2026-03-03 ┆ null │
│ 2026-03-04 ┆ 1    │
└────────────┴──────┘
2 2
```

#### Scenario: Upsample by group
- **WHEN** `upsample` is called with `groupBy`
- **THEN** each group is filled between its own first and last time
