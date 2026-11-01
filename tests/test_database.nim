import std/[unittest, os, options]
import nanuq, nanuq/database
import db_connector/db_sqlite

suite "database":
  let path = getTempDir() / "nanuq_bears.db"
  removeFile(path)
  let db = open(path, "", "", "")

  test "write and read":
    let df = newDataFrame(series("bear", @["Ada", "Bo"]), series("kg", @[410, 380]),
                          series("w", [some(1.5), none(float)]), series("ok", @[true, false]))
    check df.writeDatabase("bears", db) == 2
    let r = readDatabase("select * from bears order by kg desc", db)
    check r.columns == @["bear", "kg", "w", "ok"]
    check r.toList("bear", string) == @["Ada", "Bo"]
    check r.dtype("kg") == Int64
    check r.toList("w", Option[float]) == @[some(1.5), none(float)]
    check readDatabase("select bear from bears where kg > 400", db).height == 1

  test "if table exists":
    let df = newDataFrame(series("bear", @["Cy"]), series("kg", @[500]),
                          series("w", @[2.0]), series("ok", @[true]))
    expect ValueError:
      discard df.writeDatabase("bears", db)
    check df.writeDatabase("bears", db, IfTableExists.Append) == 1
    check readDatabase("select count(*) as n from bears", db).toList("n", int) == @[3]
    discard df.writeDatabase("bears", db, IfTableExists.Replace)
    check readDatabase("select * from bears", db).height == 1

  test "types":
    db.exec(sql"create table t (i integer, f real, s text, b blob, n integer)")
    db.exec(sql"insert into t values (1, 1.5, 'x', x'00ff', null)")
    let r = readDatabase("select * from t", db, schemaOverrides = {"i": Int32})
    check r.dtype("i") == Int32
    check r.dtype("f") == Float64
    check r.dtype("s") == String
    check r.dtype("b") == Binary
    check r.toList("b", string) == @["\x00\xff"]
    check r.dtype("n") == Int64

  test "uri":
    check readDatabaseUri("select * from t", "sqlite:///" & path).height == 1
    expect ValueError:
      discard readDatabaseUri("select 1", "postgres://x")

  test "bad query":
    expect IOError:
      discard readDatabase("select * from nope", db)

  db.close
