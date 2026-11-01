import std/[unittest, os]
import nanuq

suite "sql":
  let bears = newDataFrame:
    bear: ["Ada", "Bo", "Cy"]
    kg: [410, 380, 500]
    den: [1, 2, 1]
  let dens = newDataFrame:
    den: [1, 2]
    site: ["Kong Karls Land", "Hopen"]

  test "context":
    let ctx = newSQLContext({"bears": bears.lazy})
    check ctx.tables == @["bears"]
    let r = ctx.execute("SELECT bear, kg FROM bears WHERE kg > 400 ORDER BY kg DESC", eager = true)
    check r.toList("bear", string) == @["Cy", "Ada"]
    ctx.register("dens", dens)
    check ctx.tables == @["bears", "dens"]
    ctx.unregister("dens")
    check ctx.tables == @["bears"]
    expect SqlError:
      discard ctx.execute("SELECT * FROM nope").collect

  test "by variable name":
    let ctx = sqlContext(bears, dens)
    let r = ctx.execute("SELECT bear, site FROM bears JOIN dens USING (den) ORDER BY bear").collect
    check r.toList("site", string) == @["Kong Karls Land", "Hopen", "Kong Karls Land"]
    check not compiles(sqlContext(bears.lazy))

  test "on frames":
    let r = bears.sql("SELECT den, SUM(kg) AS kg FROM self GROUP BY den ORDER BY den")
    check r.toList("kg", int) == @[910, 380]
    check bears.sql("SELECT * FROM b", tableName = "b").height == 3
    check sql("SELECT COUNT(*) AS n FROM bears", {"bears": bears}).toList("n", int) == @[3]

  test "table functions":
    let path = getTempDir() / "nanuq_sql.csv"
    bears.writeCsv(path)
    let r = newSQLContext().execute("SELECT * FROM read_csv('" & path & "')", eager = true)
    check r.height == 3
