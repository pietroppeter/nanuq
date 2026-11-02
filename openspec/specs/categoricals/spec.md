# categoricals Specification

## Purpose
Categorical and Enum columns: Nim enums as Polars Enums, run-time Enum and Categorical dtypes, and the `cat` namespace.

## Requirements

### Requirement: Nim enums as Enum columns
A Nim enum type SHALL map to a Polars Enum whose categories are `$` of its values in
order. `series`, the block form of `newDataFrame`, `cast(T)`, `toList`, `df[c, i, T]`,
comparisons and `isIn` SHALL accept the enum type or its values. Reading a value that
is not in the enum SHALL raise `InvalidOperationError`.

```nim
type Monument = enum
  Sanremo = "Milano-Sanremo", Flanders = "Ronde van Vlaanderen",
  Roubaix = "Paris-Roubaix", Liege = "Liège-Bastogne-Liège", Lombardia = "Il Lombardia"
let wins = newDataFrame:
  race: ["Il Lombardia", "Milano-Sanremo", "Paris-Roubaix"]
  winner: ["Pogačar", "Pogačar", "van der Poel"]
let byRace = wins.withColumns(col.race.cast(Monument)).sort("race")
echo byRace
echo byRace.toList("race", Monument)
echo byRace.filter(col.race == Roubaix).toList("winner", string)
```

```text
shape: (3, 2)
┌────────────────┬──────────────┐
│ race           ┆ winner       │
│ ---            ┆ ---          │
│ enum           ┆ str          │
╞════════════════╪══════════════╡
│ Milano-Sanremo ┆ Pogačar      │
│ Paris-Roubaix  ┆ van der Poel │
│ Il Lombardia   ┆ Pogačar      │
└────────────────┴──────────────┘
@[Milano-Sanremo, Paris-Roubaix, Il Lombardia]
@["van der Poel"]
```

#### Scenario: Calendar order
- **WHEN** a column of Monument names is cast to `Monument` and sorted
- **THEN** the rows follow the order of the enum, not the alphabet

#### Scenario: Unknown value
- **WHEN** a string that is not a category is cast to `Monument` strictly
- **THEN** `InvalidOperationError` is raised

### Requirement: Run-time Enum and Categorical
`Enum(categories)` SHALL build an Enum dtype from strings, raising `ValueError` on
duplicates, and `Categorical` SHALL be the dtype of strings with categories found in
the data. Both SHALL read back as strings.

```nim
let df = newDataFrame:
  team: ["UAE", "Visma", "UAE"]
  level: ["high", "low", "high"]
let t = df.select(col.team.cast(Categorical), col.level.cast(Enum(["low", "high"])))
echo t.schema
echo t.sort("level").toList("level", string)
```

```text
{"team": Categorical, "level": Enum(["low", "high"])}
@["low", "high", "high"]
```

#### Scenario: Categories of an Enum
- **WHEN** `dtype(df, c).categories` is read for a column cast to `Enum(["low", "high"])`
- **THEN** it is `@["low", "high"]`

### Requirement: The cat namespace
`e.cat` SHALL give access to `lenBytes`, `lenChars`, `startsWith(prefix)`,
`endsWith(suffix)` and `slice(offset, length)` on Categorical and Enum columns.
`e.toPhysical` SHALL give the category indices. `getCategories`, removed in Polars 2.0,
SHALL be a compile-time error pointing to `unique()` and the dtype's `categories`.

```nim
type Medal = enum Gold, Silver, Bronze
let df = newDataFrame:
  medal: [Silver, Gold, Silver]
echo df.select(col.medal.cat.lenChars)
echo df.select(col.medal.toPhysical).toList("medal", int)
echo df.dtype("medal").categories
```

```text
shape: (3, 1)
┌───────┐
│ medal │
│ ---   │
│ u32   │
╞═══════╡
│ 6     │
│ 4     │
│ 6     │
└───────┘
@[1, 0, 1]
@["Gold", "Silver", "Bronze"]
```

#### Scenario: All categories
- **WHEN** the categories of an Enum column holding only Silver and Gold are needed
- **THEN** `dtype(df, c).categories` gives Gold, Silver and Bronze
