# sql Specification

## Purpose
Running SQL queries on frames: contexts, frames by variable name, and SQL on a frame.

## Requirements

### Requirement: SQL contexts
`newSQLContext()` SHALL make an empty context and `newSQLContext({"name": frame})` one
with frames registered; `register(name, frame)` SHALL add a LazyFrame or DataFrame,
`unregister(name)` remove it and `tables` list the names in sorted order;
`execute(query)` SHALL run a SQL query on the registered frames and give a LazyFrame, or
a DataFrame with `eager = true`.

```nim
let bears = newDataFrame:
  bear: ["Ada", "Bo", "Cy"]
  kg: [410, 380, 500]
let ctx = newSQLContext({"bears": bears.lazy})
echo ctx.tables
echo ctx.execute("SELECT bear, kg FROM bears WHERE kg > 400 ORDER BY kg DESC", eager = true)
```

```text
@["bears"]
shape: (2, 2)
┌──────┬─────┐
│ bear ┆ kg  │
│ ---  ┆ --- │
│ str  ┆ i64 │
╞══════╪═════╡
│ Cy   ┆ 500 │
│ Ada  ┆ 410 │
└──────┴─────┘
```

#### Scenario: Unknown table
- **WHEN** a query reads a table that is not registered
- **THEN** `SqlError` is raised

### Requirement: Frames by variable name
`sqlContext(a, b, ...)` SHALL make a context with each frame registered under the name of
the variable passed.

```nim
let bears = newDataFrame:
  bear: ["Ada", "Bo"]
  den: [1, 2]
let dens = newDataFrame:
  den: [1, 2]
  site: ["Kong Karls Land", "Hopen"]
let ctx = sqlContext(bears, dens)
echo ctx.execute("SELECT bear, site FROM bears JOIN dens USING (den) ORDER BY bear").collect
```

```text
shape: (2, 2)
┌──────┬─────────────────┐
│ bear ┆ site            │
│ ---  ┆ ---             │
│ str  ┆ str             │
╞══════╪═════════════════╡
│ Ada  ┆ Kong Karls Land │
│ Bo   ┆ Hopen           │
└──────┴─────────────────┘
```

#### Scenario: Not a variable
- **WHEN** `sqlContext(bears.lazy)` is compiled
- **THEN** compilation fails with a message asking for a variable

### Requirement: SQL on a frame
`df.sql(query)` and `lf.sql(query)` SHALL run a query on the frame, which the query
calls `self` (or `tableName`), and `sql(query, {"name": frame})` SHALL run a query on
the given frames.

```nim
let df = newDataFrame:
  island: ["Biscoe", "Dream", "Biscoe"]
  kg: [4.5, 3.7, 5.1]
echo df.sql("SELECT island, AVG(kg) AS kg FROM self GROUP BY island ORDER BY island")
```

```text
shape: (2, 2)
┌────────┬─────┐
│ island ┆ kg  │
│ ---    ┆ --- │
│ str    ┆ f64 │
╞════════╪═════╡
│ Biscoe ┆ 4.8 │
│ Dream  ┆ 3.7 │
└────────┴─────┘
```

#### Scenario: Other table name
- **WHEN** `df.sql("SELECT * FROM penguins", tableName = "penguins")` is run
- **THEN** the result is the frame
