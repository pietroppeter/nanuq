# Proposal

## Why

Reading query results from a database and writing frames back is common enough that the
0.6 book map counts 10 sections needing `read_database`, `read_database_uri` or
`write_database` (user guide io/database, O'Reilly ch6, Packt ch2 and ch11, the
escobar-west cookbook ch9), and most use SQLite. Python Polars goes through
SQLAlchemy, ADBC or ConnectorX, which have no Nim counterpart, but Nim's
`db_connector` package (the database modules that left the standard library) talks to
SQLite directly.

It is the seventh change of the 0.6 release and takes the "databases" part of the
coverage roadmap (Excel and databases in "More IO").

## What Changes

- New optional module `nanuq/database` (like `nanuq/datamancer`, only it needs the
  extra package `db_connector`).
- `readDatabase(query, connection, schemaOverrides)` for an open SQLite `DbConn`: types
  from the values (INTEGER → Int64, REAL → Float64, TEXT → String, BLOB → Binary; a
  column of only nulls from its declared type).
- `readDatabaseUri(query, uri, schemaOverrides)` with `sqlite:///path` URIs.
- `writeDatabase(df, tableName, connection, ifTableExists = Fail | Replace | Append)`,
  creating the table from the frame's types, in one transaction; returns the rows
  written.

## Capabilities

### New Capabilities
- `database-io`: reading and writing SQLite databases.

## Differences from Polars

- SQLite only. Python accepts any SQLAlchemy, ADBC or DBAPI connection and URIs for
  PostgreSQL, MySQL and others through ConnectorX; PostgreSQL and MySQL through
  db_connector are a possible follow-up (they return values as text without types).
- No `execute_options`, `iter_batches`, `batch_size` or `infer_schema_length`; no
  `engine` choice.
- `ifTableExists` is an enum (Python strings `"fail"`, `"replace"`, `"append"`), and
  there is no `engine_options`.
- Dates, times and datetimes are written as ISO text (SQLite has no date type), as
  Python does through SQLAlchemy.

## Impact

- New `src/nanuq/database.nim`; not imported by `nanuq` itself.
- New `tests/test_database.nim`; CI installs `db_connector` with Datamancer.
