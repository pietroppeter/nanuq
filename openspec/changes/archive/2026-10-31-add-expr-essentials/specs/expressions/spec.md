# Spec Delta

## ADDED Requirements

### Requirement: Conditional expressions
The API SHALL build conditional expressions with the chain
`` `when`(cond).then(value) ``, optionally followed by more `.when(cond).then(value)` pairs
and `.otherwise(value)`. Rows matching no condition SHALL be null when there is no
`otherwise`. A chain SHALL be usable wherever an `Expr` is expected. Values SHALL be
expressions or Nim literals, and strings SHALL be literal values.

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

#### Scenario: Floor semantics
- **WHEN** `lit(-7) mod 3` and `lit(-7) div 3` are evaluated
- **THEN** the results are 2 and -3

#### Scenario: Power
- **WHEN** `col("a") ^ 2` is selected over 3
- **THEN** the result is 9

### Requirement: Rounding
`Expr` SHALL support `round(decimals = 0, mode = HalfToEven)` with a pure enum `RoundMode`
(`HalfToEven`, `HalfAwayFromZero`, `ToZero`).

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

#### Scenario: Forward with limit
- **WHEN** `col("a").forwardFill(1)` is selected over 1, null, null and 4
- **THEN** the result is 1, 1, null and 4

#### Scenario: Mean
- **WHEN** `col("a").fillNull(Mean)` is selected over 1, null and 3
- **THEN** the result is 1, 2 and 3

### Requirement: Window expressions
`Expr` SHALL support `over(partitionBy)` with one column name, a list of names, or a list
of expressions. It SHALL compute the expression per group and return one value per row.

#### Scenario: Group mean per row
- **WHEN** `col("v").mean.over("g")` is selected over groups x, x, y with values 1, 3, 10
- **THEN** the result is 2, 2 and 10

#### Scenario: Forward fill within groups
- **WHEN** `col("r").forwardFill.over("g")` runs where group y starts with a null
- **THEN** that null stays null, instead of taking the last value of group x
