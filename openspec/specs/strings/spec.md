# strings Specification

## Purpose
String expressions: the `str` namespace, `concatStr` and `format`.

## Requirements

### Requirement: The str namespace
`e.str` SHALL give access to string functions that return expressions: `lenChars`,
`lenBytes`, `toUppercase`, `toLowercase` and `reverse`. Nulls SHALL stay null in every
string function, unless stated otherwise.

```nim
let df = newDataFrame:
  rider: ["Pogačar", "Seixas", nil]
echo df.select(col.rider, col.rider.str.toUppercase.alias("upper"),
               col.rider.str.lenChars.alias("chars"), col.rider.str.lenBytes.alias("bytes"))
```

```text
shape: (3, 4)
┌─────────┬─────────┬───────┬───────┐
│ rider   ┆ upper   ┆ chars ┆ bytes │
│ ---     ┆ ---     ┆ ---   ┆ ---   │
│ str     ┆ str     ┆ u32   ┆ u32   │
╞═════════╪═════════╪═══════╪═══════╡
│ Pogačar ┆ POGAČAR ┆ 7     ┆ 8     │
│ Seixas  ┆ SEIXAS  ┆ 6     ┆ 6     │
│ null    ┆ null    ┆ null  ┆ null  │
└─────────┴─────────┴───────┴───────┘
```

#### Scenario: Characters and bytes
- **WHEN** `str.lenChars` and `str.lenBytes` run over "Pogačar"
- **THEN** the results are 7 and 8

#### Scenario: Not a string column
- **WHEN** `str.toUppercase` runs over an i64 column
- **THEN** `PolarsError` is raised when the query runs

### Requirement: Matching
The namespace SHALL provide `startsWith(prefix)`, `endsWith(suffix)`,
`contains(pattern, literal = false, strict = true)`, `find(pattern, literal = false,
strict = true)`, `countMatches(pattern, literal = false)` and `extract(pattern,
groupIndex = 1)`. Patterns SHALL be Rust regular expressions unless `literal = true`.
With `strict = false`, an invalid regex SHALL give null instead of raising.

```nim
let df = newDataFrame:
  race: ["Paris–Nice", "Milano-Sanremo", "Tour de France"]
echo df.select(col.race,
               col.race.str.contains("–", literal = true).alias("en_dash"),
               col.race.str.startsWith("Tour").alias("tour"),
               col.race.str.extract(r"^(\w+)", 1).alias("first"),
               col.race.str.countMatches("[aeiou]").alias("vowels"))
```

```text
shape: (3, 5)
┌────────────────┬─────────┬───────┬────────┬────────┐
│ race           ┆ en_dash ┆ tour  ┆ first  ┆ vowels │
│ ---            ┆ ---     ┆ ---   ┆ ---    ┆ ---    │
│ str            ┆ bool    ┆ bool  ┆ str    ┆ u32    │
╞════════════════╪═════════╪═══════╪════════╪════════╡
│ Paris–Nice     ┆ true    ┆ false ┆ Paris  ┆ 4      │
│ Milano-Sanremo ┆ false   ┆ false ┆ Milano ┆ 6      │
│ Tour de France ┆ false   ┆ true  ┆ Tour   ┆ 5      │
└────────────────┴─────────┴───────┴────────┴────────┘
```

#### Scenario: Literal vs regex
- **WHEN** `str.contains(".")` and `str.contains(".", literal = true)` run over "abc"
- **THEN** the results are true and false

#### Scenario: No match
- **WHEN** `str.extract(r"(\d+)'")` runs over "73h"
- **THEN** the result is null

#### Scenario: Invalid regex
- **WHEN** `str.contains("(")` runs, and then `str.contains("(", strict = false)`
- **THEN** the first raises `PolarsError` and the second gives null

### Requirement: Replacing and stripping
The namespace SHALL provide `replace(pattern, value, literal = false, n = 1)`,
`replaceAll(pattern, value, literal = false)`, `stripChars`, `stripCharsStart` and
`stripCharsEnd` (whitespace without an argument, otherwise the given characters),
`stripPrefix(prefix)` and `stripSuffix(suffix)`. In a regex replacement, `$1` SHALL
refer to a capture group.

```nim
let df = newDataFrame:
  race: ["  Paris–Nice ", "Tirreno–Adriatico", "Strade Bianche"]
echo df.select(col.race.str.stripChars.str.replaceAll("–", "-", literal = true).alias("clean"),
               col.race.str.replace(r"(\w+) (\w+)", "$2 $1").alias("swapped"))
```

```text
shape: (3, 2)
┌───────────────────┬───────────────────┐
│ clean             ┆ swapped           │
│ ---               ┆ ---               │
│ str               ┆ str               │
╞═══════════════════╪═══════════════════╡
│ Paris-Nice        ┆   Paris–Nice      │
│ Tirreno-Adriatico ┆ Tirreno–Adriatico │
│ Strade Bianche    ┆ Bianche Strade    │
└───────────────────┴───────────────────┘
```

#### Scenario: Replace the first n
- **WHEN** `str.replace("a", "o", n = 2)` runs over "banana"
- **THEN** the result is "bonona"

#### Scenario: Strip given characters
- **WHEN** `str.stripChars("*")` runs over "**win**"
- **THEN** the result is "win"

### Requirement: Slicing and padding
The namespace SHALL provide `slice(offset)` and `slice(offset, length)` (a negative
offset counts from the end), `head(n)`, `tail(n)`, `padStart(length, fillChar = ' ')`,
`padEnd(length, fillChar = ' ')` and `zfill(length)`, counting characters.

```nim
let df = newDataFrame:
  bib: ["1", "21", "141"]
  nat: ["SLO", "FRA", "DEN"]
echo df.select(col.bib.str.zfill(3).alias("bib"), col.bib.str.padStart(4, '.').alias("dots"),
               col.nat.str.head(2).alias("head"), col.nat.str.slice(-2).alias("last2"))
```

```text
shape: (3, 4)
┌─────┬──────┬──────┬───────┐
│ bib ┆ dots ┆ head ┆ last2 │
│ --- ┆ ---  ┆ ---  ┆ ---   │
│ str ┆ str  ┆ str  ┆ str   │
╞═════╪══════╪══════╪═══════╡
│ 001 ┆ ...1 ┆ SL   ┆ LO    │
│ 021 ┆ ..21 ┆ FR   ┆ RA    │
│ 141 ┆ .141 ┆ DE   ┆ EN    │
└─────┴──────┴──────┴───────┘
```

#### Scenario: Slice with a length
- **WHEN** `str.slice(1, 2)` runs over "Pogačar"
- **THEN** the result is "og"

### Requirement: Joining strings in an aggregation
`str.join(delimiter = "", ignoreNulls = true)` SHALL aggregate a column into one string,
in row order, per group in `agg`. With `ignoreNulls = false`, a null SHALL make the
result null.

```nim
let wins = newDataFrame:
  rider: ["Pogačar", "Seixas", "Pogačar"]
  race: ["Strade Bianche", "Flèche Wallonne", "Il Lombardia"]
echo wins.groupBy(col.rider).agg(col.race.str.join(", ").alias("races")).sort("rider")
```

```text
shape: (2, 2)
┌─────────┬──────────────────────────────┐
│ rider   ┆ races                        │
│ ---     ┆ ---                          │
│ str     ┆ str                          │
╞═════════╪══════════════════════════════╡
│ Pogačar ┆ Strade Bianche, Il Lombardia │
│ Seixas  ┆ Flèche Wallonne              │
└─────────┴──────────────────────────────┘
```

#### Scenario: Whole column
- **WHEN** `select(col.race.str.join("|"))` runs over "a", null, "b"
- **THEN** the result is one row holding "a|b"

### Requirement: Building strings from columns
`concatStr(exprs, separator = "", ignoreNulls = false)` SHALL concatenate expressions row
by row into a string column, and `format(template, args...)` SHALL replace each `{}` in
`template` by the next argument. Non-string arguments SHALL be formatted as Polars casts
them to strings. A null argument SHALL make the row null, unless `ignoreNulls = true` in
`concatStr`. A template whose placeholders don't match the number of arguments SHALL
raise `ValueError`.

```nim
let gaps = newDataFrame:
  rider: ["Vingegaard", "Pogačar"]
  minutes: [4, 0]
  seconds: [23, 7]
echo gaps.select(format("{}: {}′ {}″", col.rider, col.minutes, col.seconds).alias("gap"),
                 concatStr([col.rider, lit("UAE")], separator = " / ").alias("team"))
```

```text
shape: (2, 2)
┌────────────────────┬──────────────────┐
│ gap                ┆ team             │
│ ---                ┆ ---              │
│ str                ┆ str              │
╞════════════════════╪══════════════════╡
│ Vingegaard: 4′ 23″ ┆ Vingegaard / UAE │
│ Pogačar: 0′ 7″     ┆ Pogačar / UAE    │
└────────────────────┴──────────────────┘
```

#### Scenario: Wrong number of arguments
- **WHEN** `format("{} {}", col.a)` is called
- **THEN** `ValueError` is raised

#### Scenario: Next to strutils
- **WHEN** a module imports `std/strutils` and `nanuq` and calls `format("{}", col.a)` and `"$1".format("x")`
- **THEN** both compile, the first giving an expression and the second "x"

### Requirement: Title case
`str.toTitlecase` SHALL upper-case the first letter of each word and lower-case the
rest, when the native library is built with the `nightly` feature, as the release
libraries are. With a library built without it, it SHALL raise `InvalidOperationError`
when the expression is built.

#### Scenario: Release library
- **WHEN** `str.toTitlecase` runs over "tour de france" with a release library
- **THEN** the result is "Tour De France"

#### Scenario: Stable build
- **WHEN** `str.toTitlecase` is called with a library built on stable Rust
- **THEN** `InvalidOperationError` is raised

### Requirement: Splitting and extracting into lists and structs
`str.split(by)` SHALL split each string into a `list[str]` (keeping `by` with
`inclusive = true`), `str.extractAll(pattern)` SHALL give all regex matches as a list,
`str.splitExact(by, n)` and `str.splitn(by, n)` SHALL give a struct of `n + 1` or `n`
fields named `field_0`, ..., and `str.extractGroups(pattern)` SHALL give a struct with
one field per capture group, named after named groups or numbered from 1.

```nim
let df = newDataFrame:
  station: ["Lima, Peru", "Piura, Peru", "Darwin"]
echo df.select(col("station").str.split(", ").alias("parts"),
               col("station").str.splitExact(", ", 1).alias("exact"),
               col("station").str.extractGroups(r"(?<city>\w+)(, (?<country>\w+))?").alias("groups"))
```

```text
shape: (3, 3)
┌───────────────────┬──────────────────┬───────────────────────────┐
│ parts             ┆ exact            ┆ groups                    │
│ ---               ┆ ---              ┆ ---                       │
│ list[str]         ┆ struct[2]        ┆ struct[3]                 │
╞═══════════════════╪══════════════════╪═══════════════════════════╡
│ ["Lima", "Peru"]  ┆ {"Lima","Peru"}  ┆ {"Lima",", Peru","Peru"}  │
│ ["Piura", "Peru"] ┆ {"Piura","Peru"} ┆ {"Piura",", Peru","Peru"} │
│ ["Darwin"]        ┆ {"Darwin",null}  ┆ {"Darwin",null,null}      │
└───────────────────┴──────────────────┴───────────────────────────┘
```

#### Scenario: Missing parts
- **WHEN** `splitExact(", ", 1)` is evaluated on a string without a comma
- **THEN** the second field is null

### Requirement: Many patterns at once
`str.containsAny(patterns)`, `str.replaceMany(patterns, replaceWith)` (or a mapping),
`str.extractMany(patterns)` and `str.findMany(patterns)` SHALL match many literal
patterns in one pass, with `asciiCaseInsensitive` and, for extract and find,
`overlapping`.

```nim
let df = newDataFrame:
  note: ["sea ice thin", "no ice", "open water"]
echo df.select(col("note").str.containsAny(["ice", "water"]).alias("any"),
               col("note").str.replaceMany({"ice": "ICE", "water": "WATER"}).alias("loud"),
               col("note").str.extractMany(["ice", "sea", "water"]).alias("found"))
```

```text
shape: (3, 3)
┌──────┬──────────────┬────────────────┐
│ any  ┆ loud         ┆ found          │
│ ---  ┆ ---          ┆ ---            │
│ bool ┆ str          ┆ list[str]      │
╞══════╪══════════════╪════════════════╡
│ true ┆ sea ICE thin ┆ ["sea", "ice"] │
│ true ┆ no ICE       ┆ ["ice"]        │
│ true ┆ open WATER   ┆ ["water"]      │
└──────┴──────────────┴────────────────┘
```

#### Scenario: One replacement for all
- **WHEN** `replaceMany(["a", "b"], "_")` is evaluated on "abc"
- **THEN** the result is "__c"

### Requirement: JSON in strings
`str.jsonDecode(dtype)` (or `jsonDecode(T)` with a Nim type) SHALL parse each string as
JSON into a value of `dtype`, and `str.jsonPathMatch(path)` SHALL give the string at a
JSONPath, null when there is none.

```nim
let df = newDataFrame:
  json: ["""{"bear": "Ada", "kg": 410}""", """{"bear": "Bo", "kg": null}"""]
echo df.select(col("json").str.jsonDecode(tuple[bear: string, kg: Option[int]]).alias("v"),
               col("json").str.jsonPathMatch("$.bear").alias("bear"))
```

```text
shape: (2, 2)
┌─────────────┬──────┐
│ v           ┆ bear │
│ ---         ┆ ---  │
│ struct[2]   ┆ str  │
╞═════════════╪══════╡
│ {"Ada",410} ┆ Ada  │
│ {"Bo",null} ┆ Bo   │
└─────────────┴──────┘
```

#### Scenario: Invalid JSON
- **WHEN** a string that is not JSON is decoded
- **THEN** `ComputeError` is raised

### Requirement: Escaping and normalizing
`str.escapeRegex` SHALL escape regex metacharacters, and `str.normalize(form =
UnicodeForm.NFC)` SHALL give the Unicode normal form (`NFC`, `NFKC`, `NFD`, `NFKD`).

```nim
let df = newDataFrame(series("s", @["a.b*c", "é"]))
echo df.select(col("s").str.escapeRegex.alias("escaped"),
               col("s").str.normalize.str.lenChars.alias("chars"))
```

```text
shape: (2, 2)
┌─────────┬───────┐
│ escaped ┆ chars │
│ ---     ┆ ---   │
│ str     ┆ u32   │
╞═════════╪═══════╡
│ a\.b\*c ┆ 5     │
│ é       ┆ 1     │
└─────────┴───────┘
```

#### Scenario: Composed form
- **WHEN** "e" followed by a combining acute accent is normalized to NFC
- **THEN** the result is the one character "é"
