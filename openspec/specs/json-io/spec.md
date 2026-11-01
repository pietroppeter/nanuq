# json-io Specification

## Purpose
Reading and writing JSON and NDJSON.

## Requirements

### Requirement: Reading JSON
`readJson(source)` SHALL read a JSON array of objects (one row each) from a file path or
a Stream, and `readNdjson(source)` newline-delimited JSON, with nested values becoming
List and Struct columns. `schema` SHALL fix all column types, `schemaOverrides` some of
them, `inferSchemaLength` SHALL bound the rows used to infer the rest, and `ignoreErrors`
SHALL read values that do not parse as null.

```nim
import std/streams
let json = """[{"bear": "Ada", "cubs": ["Bo"], "den": {"lat": 78.2}},
               {"bear": "Cy", "cubs": [], "den": {"lat": 79.0}}]"""
let df = readJson(newStringStream(json))
echo df
echo readNdjson(newStringStream("{\"a\": 1}\n{\"a\": 2}\n"), schemaOverrides = {"a": Float64})
```

```text
shape: (2, 3)
┌──────┬───────────┬───────────┐
│ bear ┆ cubs      ┆ den       │
│ ---  ┆ ---       ┆ ---       │
│ str  ┆ list[str] ┆ struct[1] │
╞══════╪═══════════╪═══════════╡
│ Ada  ┆ ["Bo"]    ┆ {78.2}    │
│ Cy   ┆ []        ┆ {79.0}    │
└──────┴───────────┴───────────┘
shape: (2, 1)
┌─────┐
│ a   │
│ --- │
│ f64 │
╞═════╡
│ 1.0 │
│ 2.0 │
└─────┘
```

#### Scenario: Not JSON
- **WHEN** a file that is not JSON is read with `readJson`
- **THEN** `ComputeError` is raised

### Requirement: Scanning NDJSON
`scanNdjson(path)` SHALL read newline-delimited JSON files lazily (a path or a glob),
with `nRows`, `rowIndexName` and `rowIndexOffset` and the schema options of
`readNdjson`.

```nim
let path = getTempDir() / "bears.ndjson"
writeFile(path, "{\"bear\": \"Ada\", \"kg\": 410}\n{\"bear\": \"Bo\", \"kg\": 380}\n")
echo scanNdjson(path, rowIndexName = "i").filter(col("kg") > 400).collect
```

```text
shape: (1, 3)
┌─────┬──────┬─────┐
│ i   ┆ bear ┆ kg  │
│ --- ┆ ---  ┆ --- │
│ u32 ┆ str  ┆ i64 │
╞═════╪══════╪═════╡
│ 0   ┆ Ada  ┆ 410 │
└─────┴──────┴─────┘
```

#### Scenario: Limit rows
- **WHEN** a file of 3 lines is scanned with `nRows = 2`
- **THEN** the frame has 2 rows

### Requirement: Writing JSON
`writeJson(dest)` SHALL write a frame as a JSON array of row objects to a path or a
Stream, `writeNdjson(dest)` one object per line, and `toJson`/`toNdjson` SHALL return the
same text; reading it back SHALL give the same frame.

```nim
let df = newDataFrame:
  bear: ["Ada", "Bo"]
  cubs: [@["Cy"], @[]]
echo df.toJson
echo df.toNdjson
```

```text
[{"bear":"Ada","cubs":["Cy"]},{"bear":"Bo","cubs":[]}]
{"bear":"Ada","cubs":["Cy"]}
{"bear":"Bo","cubs":[]}
```

#### Scenario: Round trip
- **WHEN** a frame with list and struct columns is written with `writeNdjson` and read with `readNdjson`
- **THEN** the result equals the frame
