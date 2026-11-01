# Spec Delta

## ADDED Requirements

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
TBD
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
TBD
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
TBD
```

#### Scenario: Invalid JSON
- **WHEN** a string that is not JSON is decoded
- **THEN** `ComputeError` is raised
