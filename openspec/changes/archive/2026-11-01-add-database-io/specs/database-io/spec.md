# Spec Delta

## ADDED Requirements

### Requirement: Writing to a database
`writeDatabase(df, tableName, connection, ifTableExists = IfTableExists.Fail)` in
`nanuq/database` SHALL write the frame's rows to a SQLite table, creating it with column
types from the frame (integers and booleans INTEGER, floats REAL, Binary BLOB, the rest
TEXT), and return the number of rows written. An existing table SHALL raise `ValueError`
with `Fail`, be dropped first with `Replace`, and receive the rows with `Append`.

```nim
import nanuq/database, db_connector/db_sqlite
let db = open(":memory:", "", "", "")
let df = newDataFrame(series("bear", @["Ada", "Bo"]), series("kg", @[410, 380]))
echo df.writeDatabase("bears", db)
echo df.writeDatabase("bears", db, IfTableExists.Append)
```

```text
TBD
```

#### Scenario: Table exists
- **WHEN** a frame is written to an existing table with `IfTableExists.Fail`
- **THEN** `ValueError` is raised and the table is unchanged

### Requirement: Reading from a database
`readDatabase(query, connection, schemaOverrides = [])` SHALL run a query on an open
SQLite connection and return its rows, with INTEGER values as Int64, REAL (or mixed
numbers) as Float64, TEXT as String and BLOB as Binary, and a column of only nulls typed
from its declared type. `readDatabaseUri(query, "sqlite:///path")` SHALL open the
database for the query and close it.

```nim
import nanuq/database, db_connector/db_sqlite
let db = open(":memory:", "", "", "")
discard newDataFrame(series("bear", @["Ada", "Bo"]), series("kg", @[410.5, 380.0])).writeDatabase("bears", db)
echo readDatabase("select bear, kg * 2 as double from bears where kg > 400", db)
```

```text
TBD
```

#### Scenario: Bad query
- **WHEN** the query names a table that does not exist
- **THEN** `IOError` is raised

#### Scenario: Other URIs
- **WHEN** `readDatabaseUri` gets a `postgres://` URI
- **THEN** `ValueError` is raised
