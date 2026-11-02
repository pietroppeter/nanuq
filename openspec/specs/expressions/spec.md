# expressions Specification

## Purpose
Expressions beyond the basics: conditionals, membership and range tests, extra arithmetic,
rounding and aggregations, null fill strategies, and window expressions.

## Requirements

### Requirement: Conditional expressions
The API SHALL build conditional expressions with the chain
`` `when`(cond).then(value) ``, optionally followed by more `.when(cond).then(value)` pairs
and `.otherwise(value)`. Rows matching no condition SHALL be null when there is no
`otherwise`. A chain SHALL be usable wherever an `Expr` is expected. Values SHALL be
expressions or Nim literals, and strings SHALL be literal values.

```nim
let bears = newDataFrame(series("w", [100, 300, 900]))
echo bears.select(
  `when`(col("w") < 150).then("cub")
  .when(col("w") < 500).then("adult")
  .otherwise("chonk")
  .alias("size"))
```

```text
shape: (3, 1)
┌───────┐
│ size  │
│ ---   │
│ str   │
╞═══════╡
│ cub   │
│ adult │
│ chonk │
└───────┘
```

#### Scenario: Three-way label
- **WHEN** `` `when`(col("w") < 150).then("cub").when(col("w") < 500).then("adult").otherwise("chonk") `` is selected over weights 100, 300 and 900
- **THEN** the result is "cub", "adult" and "chonk"

#### Scenario: No otherwise
- **WHEN** `` `when`(col("w") < 150).then(1) `` is selected over weights 100 and 900
- **THEN** the result is 1 and null

### Requirement: choose macro
The API SHALL provide a `choose` macro that turns an `if`/`elif`/`else` expression with
expression conditions into the same chain. A missing `else` SHALL mean null. Any other
body SHALL fail to compile.

```nim
let bears = newDataFrame(series("w", [100, 300, 900]))
let size = choose:
  if col("w") < 150: "cub"
  elif col("w") < 500: "adult"
  else: "chonk"
echo bears.select(col("w"), size.alias("size"))
```

```text
shape: (3, 2)
┌─────┬───────┐
│ w   ┆ size  │
│ --- ┆ ---   │
│ i64 ┆ str   │
╞═════╪═══════╡
│ 100 ┆ cub   │
│ 300 ┆ adult │
│ 900 ┆ chonk │
└─────┴───────┘
```

#### Scenario: Same plan as the chain
- **WHEN** a `choose` block and the equivalent chain are built
- **THEN** their `$` strings are equal

#### Scenario: One line
- **WHEN** `choose(if col("collared"): "tracked" else: "free")` is selected
- **THEN** each row is "tracked" or "free"

### Requirement: Membership and ranges
`Expr` SHALL support `isIn(values)` for a list of Nim values or an expression, with
`nullsEqual = false`, and `isBetween(lower, upper, closed = Both)` with a pure enum
`ClosedInterval` (`Both`, `Left`, `Right`, `None`).

```nim
let df = newDataFrame(series("a", [1, 2, 3]))
echo df.select(
  col("a"),
  col("a").isIn([1, 3]).alias("in_1_3"),
  col("a").isBetween(1, 3, closed = Left).alias("in_[1,3)"))
```

```text
shape: (3, 3)
┌─────┬────────┬──────────┐
│ a   ┆ in_1_3 ┆ in_[1,3) │
│ --- ┆ ---    ┆ ---      │
│ i64 ┆ bool   ┆ bool     │
╞═════╪════════╪══════════╡
│ 1   ┆ true   ┆ true     │
│ 2   ┆ false  ┆ true     │
│ 3   ┆ true   ┆ false    │
└─────┴────────┴──────────┘
```

#### Scenario: isIn
- **WHEN** `col("a").isIn([1, 3])` is selected over 1, 2 and 3
- **THEN** the result is true, false and true

#### Scenario: Half-open range
- **WHEN** `col("a").isBetween(1, 3, closed = Left)` is selected over 1, 2 and 3
- **THEN** the result is true, true and false

### Requirement: Arithmetic operators
`Expr` SHALL support `mod`, `div` (floor division), `^` and `pow`, `abs` and unary `-`,
with Nim literals on either side of a binary operator. `mod` and `div` SHALL follow
Polars' floor semantics.

```nim
let df = newDataFrame(series("a", [-7, 3]))
echo df.select(col("a"), (col("a") mod 3).alias("mod"), (col("a") div 3).alias("div"),
               (col("a") ^ 2).alias("sq"), abs(col("a")).alias("abs"))
```

```text
shape: (2, 5)
┌─────┬─────┬─────┬─────┬─────┐
│ a   ┆ mod ┆ div ┆ sq  ┆ abs │
│ --- ┆ --- ┆ --- ┆ --- ┆ --- │
│ i64 ┆ i64 ┆ i64 ┆ i64 ┆ i64 │
╞═════╪═════╪═════╪═════╪═════╡
│ -7  ┆ 2   ┆ -3  ┆ 49  ┆ 7   │
│ 3   ┆ 0   ┆ 1   ┆ 9   ┆ 3   │
└─────┴─────┴─────┴─────┴─────┘
```

#### Scenario: Floor semantics
- **WHEN** `lit(-7) mod 3` and `lit(-7) div 3` are evaluated
- **THEN** the results are 2 and -3

#### Scenario: Power
- **WHEN** `col("a") ^ 2` is selected over 3
- **THEN** the result is 9

### Requirement: Rounding
`Expr` SHALL support `round(decimals = 0, mode = HalfToEven)` with a pure enum `RoundMode`
(`HalfToEven`, `HalfAwayFromZero`, `ToZero`).

```nim
let df = newDataFrame(series("w", [1.23456, 2.5]))
echo df.select(col("w").round(2).alias("r2"), col("w").round.alias("even"),
               col("w").round(mode = HalfAwayFromZero).alias("away"))
```

```text
shape: (2, 3)
┌──────┬──────┬──────┐
│ r2   ┆ even ┆ away │
│ ---  ┆ ---  ┆ ---  │
│ f64  ┆ f64  ┆ f64  │
╞══════╪══════╪══════╡
│ 1.23 ┆ 1.0  ┆ 1.0  │
│ 2.5  ┆ 2.0  ┆ 3.0  │
└──────┴──────┴──────┘
```

#### Scenario: Two decimals
- **WHEN** `col("w").round(2)` is selected over 1.23456
- **THEN** the result is 1.23

#### Scenario: Half to even by default
- **WHEN** `col("w").round` and `col("w").round(mode = HalfAwayFromZero)` are selected over 2.5
- **THEN** the results are 2.0 and 3.0

### Requirement: More aggregations
`Expr` SHALL support `median`, `var(ddof = 1)`, `std(ddof = 1)`, `quantile(q, interpolation =
Nearest)` with a pure enum `QuantileMethod` (`Nearest`, `Lower`, `Higher`, `Midpoint`,
`Linear`, `Equiprobable`), and `len`, which counts rows including nulls.

```nim
let df = newDataFrame(series("a", [some(1), some(2), none(int), some(4)]))
echo df.select(col("a").median.alias("median"),
               col("a").quantile(0.5, interpolation = Linear).alias("q50"),
               col("a").len.alias("len"), col("a").count.alias("count"))
```

```text
shape: (1, 4)
┌────────┬─────┬─────┬───────┐
│ median ┆ q50 ┆ len ┆ count │
│ ---    ┆ --- ┆ --- ┆ ---   │
│ f64    ┆ f64 ┆ u32 ┆ u32   │
╞════════╪═════╪═════╪═══════╡
│ 2.0    ┆ 2.0 ┆ 4   ┆ 3     │
└────────┴─────┴─────┴───────┘
```

#### Scenario: Median and quantile
- **WHEN** `median` and `quantile(0.25, interpolation = Linear)` are computed over 1, 2, 3 and 4
- **THEN** the results are 2.5 and 1.75

#### Scenario: len vs count
- **WHEN** `len` and `count` are computed over 1, null and 3
- **THEN** the results are 3 and 2

### Requirement: Null fill strategies
`Expr` SHALL support `fillNull(strategy, limit = none(int))` with a pure enum
`FillNullStrategy` (`Forward`, `Backward`, `Mean`, `Min`, `Max`, `Zero`, `One`), and the
shortcuts `forwardFill(limit)` and `backwardFill(limit)`. `limit` SHALL also accept a
plain `int`. A limit SHALL bound how many consecutive nulls are filled.

```nim
let df = newDataFrame(series("a", [some(1), none(int), none(int), some(4)]))
echo df.select(col("a"), col("a").forwardFill(1).alias("ffill1"),
               col("a").backwardFill.alias("bfill"), col("a").fillNull(Mean).alias("mean"))
```

```text
shape: (4, 4)
┌──────┬────────┬───────┬──────┐
│ a    ┆ ffill1 ┆ bfill ┆ mean │
│ ---  ┆ ---    ┆ ---   ┆ ---  │
│ i64  ┆ i64    ┆ i64   ┆ i64  │
╞══════╪════════╪═══════╪══════╡
│ 1    ┆ 1      ┆ 1     ┆ 1    │
│ null ┆ 1      ┆ 4     ┆ 2    │
│ null ┆ null   ┆ 4     ┆ 2    │
│ 4    ┆ 4      ┆ 4     ┆ 4    │
└──────┴────────┴───────┴──────┘
```

#### Scenario: Forward with limit
- **WHEN** `col("a").forwardFill(1)` is selected over 1, null, null and 4
- **THEN** the result is 1, 1, null and 4

#### Scenario: Mean
- **WHEN** `col("a").fillNull(Mean)` is selected over 1, null and 3
- **THEN** the result is 1, 2 and 3

### Requirement: Window expressions
`Expr` SHALL support `over(partitionBy)` with one column name, a list of names, or a list
of expressions. It SHALL compute the expression per group and return one value per row.

```nim
let df = newDataFrame(series("g", ["x", "x", "y"]), series("v", [1, 3, 10]))
echo df.withColumns(col("v").mean.over("g").alias("group_mean"))
```

```text
shape: (3, 3)
┌─────┬─────┬────────────┐
│ g   ┆ v   ┆ group_mean │
│ --- ┆ --- ┆ ---        │
│ str ┆ i64 ┆ f64        │
╞═════╪═════╪════════════╡
│ x   ┆ 1   ┆ 2.0        │
│ x   ┆ 3   ┆ 2.0        │
│ y   ┆ 10  ┆ 10.0       │
└─────┴─────┴────────────┘
```

#### Scenario: Group mean per row
- **WHEN** `col("v").mean.over("g")` is selected over groups x, x, y with values 1, 3, 10
- **THEN** the result is 2, 2 and 10

#### Scenario: Forward fill within groups
- **WHEN** `col("r").forwardFill.over("g")` runs where group y starts with a null
- **THEN** that null stays null, instead of taking the last value of group x

### Requirement: Ranking
`Expr` SHALL support `rank(how = Average, descending = false, seed = none(int))`
with a pure enum `RankMethod` (`Average`, `Min`, `Max`, `Dense`, `Ordinal`, `Random`),
giving each value its rank from 1. Ties SHALL be handled as Polars does: `Average` gives
tied values the mean of their ranks (f64), `Min` and `Max` the lowest or highest (u32),
`Dense` leaves no gaps after ties, and `Ordinal` breaks ties by position. `seed` SHALL
make `Random` repeatable. Nulls SHALL stay null.

```nim
let roll = newDataFrame:
  rider: ["Merckx", "Pogačar", "De Vlaeminck", "Van Looy", "Kelly"]
  monuments: [19, 13, 11, 8, 9]
echo roll.select(col.rider, col.monuments,
                 col.monuments.rank(Min, descending = true).alias("place"),
                 col.monuments.rank.alias("avg"))
```

```text
shape: (5, 4)
┌──────────────┬───────────┬───────┬─────┐
│ rider        ┆ monuments ┆ place ┆ avg │
│ ---          ┆ ---       ┆ ---   ┆ --- │
│ str          ┆ i64       ┆ u32   ┆ f64 │
╞══════════════╪═══════════╪═══════╪═════╡
│ Merckx       ┆ 19        ┆ 1     ┆ 5.0 │
│ Pogačar      ┆ 13        ┆ 2     ┆ 4.0 │
│ De Vlaeminck ┆ 11        ┆ 3     ┆ 3.0 │
│ Van Looy     ┆ 8         ┆ 5     ┆ 1.0 │
│ Kelly        ┆ 9         ┆ 4     ┆ 2.0 │
└──────────────┴───────────┴───────┴─────┘
```

#### Scenario: Shared places
- **WHEN** `rank(Min, descending = true)` runs over 9, 9, 7
- **THEN** the result is 1, 1, 3

#### Scenario: Dense
- **WHEN** `rank(Dense)` runs over 9, 9, 7
- **THEN** the result is 2, 2, 1

#### Scenario: Average
- **WHEN** `rank()` runs over 9, 9, 7
- **THEN** the result is 2.5, 2.5, 1.0 with dtype f64

### Requirement: Filtering inside expressions
`e.filter(predicate)` SHALL keep the values of `e` where `predicate` is true, so that an
aggregation can run over part of each group.

```nim
let df = newDataFrame:
  rider: ["Pogačar", "Pogačar", "Vingegaard", "Vingegaard"]
  stage: ["TT", "road", "TT", "road"]
  secs: [3120, 15400, 3150, 15390]
echo df.groupBy(col.rider).agg(col.secs.filter(col.stage == "TT").sum.alias("tt_secs"))
  .sort("rider")
```

```text
shape: (2, 2)
┌────────────┬─────────┐
│ rider      ┆ tt_secs │
│ ---        ┆ ---     │
│ str        ┆ i64     │
╞════════════╪═════════╡
│ Pogačar    ┆ 3120    │
│ Vingegaard ┆ 3150    │
└────────────┴─────────┘
```

#### Scenario: Conditional sum
- **WHEN** `col.secs.filter(col.stage == "TT").sum` is aggregated per rider
- **THEN** each rider's sum counts only the TT rows

### Requirement: Shape and position aggregations
Expressions SHALL have the aggregations `product`, `mode` (every most frequent value, in
order of appearance), `argMin` and `argMax` (the row index of the first minimum or
maximum), `skew(bias = true)` and `kurtosis(fisher = true, bias = true)`.

```nim
let df = newDataFrame:
  year: [2020, 2021, 2022, 2023]
  oni: [0.5, -1.0, -0.9, 1.9]
echo df.select(col.oni.argMax.alias("warmest_row"),
               col.oni.argMin.alias("coldest_row"), col.oni.skew.round(3).alias("skew"))
```

```text
shape: (1, 3)
┌─────────────┬─────────────┬───────┐
│ warmest_row ┆ coldest_row ┆ skew  │
│ ---         ┆ ---         ┆ ---   │
│ u32         ┆ u32         ┆ f64   │
╞═════════════╪═════════════╪═══════╡
│ 3           ┆ 1           ┆ 0.474 │
└─────────────┴─────────────┴───────┘
```

#### Scenario: Product
- **WHEN** `product` runs on 2, 3, 4
- **THEN** the result is 24

#### Scenario: Several modes
- **WHEN** `mode` runs on 1, 2, 2, 3, 3
- **THEN** the result holds 2 and 3

### Requirement: Boolean aggregations
`Expr` SHALL support `any(ignoreNulls = true)` and `all(ignoreNulls = true)` on boolean
columns, as aggregations: whether any value, or every value, is true. With
`ignoreNulls = false` they SHALL follow Kleene logic: `any` is null when there are nulls
and no true value, `all` is null when there are nulls and no false value. The `all()`
selector (no arguments) SHALL keep working.

```nim
let df = newDataFrame:
  team: ["a", "a", "b", "b"]
  won: [true, false, true, true]
echo df.groupBy("team").agg(col.won.all.alias("always"), col.won.any.alias("ever"))
```

```text
shape: (2, 3)
┌──────┬────────┬──────┐
│ team ┆ always ┆ ever │
│ ---  ┆ ---    ┆ ---  │
│ str  ┆ bool   ┆ bool │
╞══════╪════════╪══════╡
│ a    ┆ false  ┆ true │
│ b    ┆ true   ┆ true │
└──────┴────────┴──────┘
```

#### Scenario: Kleene logic
- **WHEN** `any(ignoreNulls = false)` runs on false and null
- **THEN** the result is null

### Requirement: Entropy
`Expr` SHALL support `entropy(base = E, normalize = true)`, an aggregation giving
`-sum(p * ln(p)) / ln(base)`, where `p` are the values (divided by their sum when
`normalize` is true).

```nim
let df = newDataFrame:
  votes: [@[1, 1, 2], @[5]]
echo df.select(col.votes.list.agg(element().entropy).alias("entropy"))
```

```text
shape: (2, 1)
┌──────────┐
│ entropy  │
│ ---      │
│ f64      │
╞══════════╡
│ 1.039721 │
│ 0.0      │
└──────────┘
```

#### Scenario: One value
- **WHEN** the entropy of a single positive value is computed
- **THEN** the result is 0.0

### Requirement: Row count expression
`len()` with no argument SHALL be an expression counting rows, named `len` (Python's
`pl.len()`); in a group-by it SHALL count the rows of each group.

```nim
let df = newDataFrame:
  team: ["a", "a", "b"]
echo df.groupBy("team").agg(len())
```

```text
shape: (2, 2)
┌──────┬─────┐
│ team ┆ len │
│ ---  ┆ --- │
│ str  ┆ u32 │
╞══════╪═════╡
│ a    ┆ 2   │
│ b    ┆ 1   │
└──────┴─────┘
```

#### Scenario: Whole frame
- **WHEN** `df.select(len())` runs on 4 rows
- **THEN** the result is one row with `len` = 4

### Requirement: Several window keys and selector concatenation
`over` SHALL take several column names as separate arguments, and `concatStr` SHALL take selectors, expanding them to their columns.

```nim
let df = newDataFrame(series("c", @["x", "x", "y"]), series("b", @["p", "p", "q"]))
echo df.select(concatStr([all()], "-").alias("s"), lit(1).sum.over("c", "b").alias("n"))
```

```text
shape: (3, 2)
┌─────┬─────┐
│ s   ┆ n   │
│ --- ┆ --- │
│ str ┆ i32 │
╞═════╪═════╡
│ x-p ┆ 1   │
│ x-p ┆ 1   │
│ y-q ┆ 1   │
└─────┴─────┘
```

#### Scenario: Two keys
- **WHEN** `col("v").sum.over("c", "b")` is selected
- **THEN** each row gets the sum of its (c, b) group

### Requirement: Null-aware comparisons and closeness
`eqMissing(other)` and `neMissing(other)` SHALL compare as `==` and `!=` with null equal
to null, never giving null. `isClose(other, absTol = 0.0, relTol = 1e-9, nansEqual =
false)` SHALL be true where `abs(a - b) <= max(relTol * max(abs(a), abs(b)), absTol)`.

```nim
let df = newDataFrame(series("a", [some(1.0), none(float)]), series("b", [some(1.05), none(float)]))
echo df.select(col("a").eqMissing(col("b")).alias("eq"),
               col("a").isClose(col("b"), absTol = 0.1).alias("close"))
```

```text
shape: (2, 2)
┌───────┬───────┐
│ eq    ┆ close │
│ ---   ┆ ---   │
│ bool  ┆ bool  │
╞═══════╪═══════╡
│ false ┆ true  │
│ true  ┆ null  │
└───────┴───────┘
```

#### Scenario: Nulls
- **WHEN** `eqMissing` compares null with null
- **THEN** the result is true

### Requirement: More expression functions
`nth(indices)` SHALL select columns by position (negative from the end).
`cumulativeEval(expr, minSamples = 1)` SHALL run `expr` on the growing window up to each
row, `roundSigFigs(digits)` SHALL round to significant figures, `reinterpret(signed)`
SHALL read 64-bit integer bits as Int64 or UInt64, and `concatArr(exprs)` SHALL build
fixed-size arrays per row.

```nim
let df = newDataFrame(series("x", @[1.0, 22.0, 333.0]), series("y", @[4.0, 5.0, 6.0]))
echo df.select(nth(-1), col("x").cumulativeEval(element().sum).alias("cum"),
               col("x").roundSigFigs(1).alias("sig"), concatArr(col("x"), col("y")).alias("xy"))
```

```text
shape: (3, 4)
┌─────┬───────┬───────┬───────────────┐
│ y   ┆ cum   ┆ sig   ┆ xy            │
│ --- ┆ ---   ┆ ---   ┆ ---           │
│ f64 ┆ f64   ┆ f64   ┆ array[f64, 2] │
╞═════╪═══════╪═══════╪═══════════════╡
│ 4.0 ┆ 1.0   ┆ 1.0   ┆ [1.0, 4.0]    │
│ 5.0 ┆ 23.0  ┆ 20.0  ┆ [22.0, 5.0]   │
│ 6.0 ┆ 356.0 ┆ 300.0 ┆ [333.0, 6.0]  │
└─────┴───────┴───────┴───────────────┘
```

#### Scenario: Cumulative sum
- **WHEN** `cumulativeEval(element().sum)` runs on 1, 2, 3
- **THEN** the result is 1, 3, 6
