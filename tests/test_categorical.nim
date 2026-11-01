import std/[unittest, options, os, strutils]
import nanuq

type
  Monument = enum
    Sanremo = "Milano-Sanremo", Flanders = "Ronde van Vlaanderen", Roubaix = "Paris-Roubaix",
    Liege = "Liège-Bastogne-Liège", Lombardia = "Il Lombardia"
  Medal = enum Gold, Silver, Bronze

suite "enums from Nim":
  test "dataType of a Nim enum":
    check dataType(Medal) == Enum(["Gold", "Silver", "Bronze"])
    check $dataType(Medal) == """Enum(["Gold", "Silver", "Bronze"])"""
    check dataType(Monument).categories[1] == "Ronde van Vlaanderen"

  test "series, block syntax and reading back":
    let df = newDataFrame:
      race: [Roubaix, Sanremo, nil]
      medal: [Gold, Gold, Bronze]
    check df.dtype("race") == Monument
    check df.dtype("race") == dataType(Monument)
    check df.dtype("medal") == Medal
    check df.toList("medal", Medal) == @[Gold, Gold, Bronze]
    check df.toList("race", Option[Monument]) == @[some(Roubaix), some(Sanremo), none(Monument)]
    check df.toList("race", Option[string])[0] == some("Paris-Roubaix")
    check df["medal", 2, Medal] == Bronze
    check df["race", 2, Option[Monument]].isNone

  test "cast strings to a Nim enum":
    let df = newDataFrame(series("race", ["Il Lombardia", "Paris-Roubaix"]))
    let e = df.select(col.race.cast(Monument))
    check e.toList("race", Monument) == @[Lombardia, Roubaix]
    expect InvalidOperationError:
      discard newDataFrame(series("race", ["Tour de France"])).select(col.race.cast(Monument))
    check newDataFrame(series("race", ["Tour de France"]))
      .select(col.race.cast(Monument, strict = false)).toList("race", Option[Monument]) ==
      @[none(Monument)]

  test "Enum order sorts and compares":
    let df = newDataFrame:
      medal: [Bronze, Gold, Silver]
      rider: ["c", "a", "b"]
    check df.sort("medal").toList("rider", string) == @["a", "b", "c"]
    check df.filter(col.medal == Gold).toList("rider", string) == @["a"]
    check df.filter(col.medal.isIn([Gold, Silver])).height == 2
    check df.select(col.medal.toPhysical).toList("medal", int) == @[2, 0, 1]

  test "reading a value that is not in the Nim enum":
    let df = newDataFrame(series("m", ["Gold", "Platinum"])).select(
      col.m.cast(Enum(["Gold", "Platinum"])))
    expect InvalidOperationError:
      discard df.toList("m", Medal)

suite "run-time Enum and Categorical":
  test "Enum from strings":
    let t = Enum(["low", "high"])
    let df = newDataFrame(series("x", ["high", "low", "high"])).select(col.x.cast(t))
    check df.dtype("x") == t
    check df.dtype("x").categories == @["low", "high"]
    check not compiles(col.x.cat.getCategories)  # removed in Polars 2.0
    expect ValueError:
      discard Enum(["a", "a"])

  test "Categorical":
    let df = newDataFrame(series("team", ["UAE", "Visma", "UAE"])).select(col.team.cast(Categorical))
    check df.dtype("team") == Categorical
    check $df.dtype("team") == "Categorical"
    check df.toList("team", string) == @["UAE", "Visma", "UAE"]
    check df.select(col.team.nUnique).toList("team", int) == @[2]
    check df.groupBy(col.team).agg(col.team.count.alias("n")).height == 2

  test "cat functions":
    let df = newDataFrame:
      race: [Flanders, Liege]
    check df.select(col.race.cat.lenChars).toList("race", int) == @[20, 20]
    check df.select(col.race.cat.lenBytes).toList("race", int) == @[20, 22]
    check df.select(col.race.cat.startsWith("Ronde")).toList("race", bool) == @[true, false]
    check df.select(col.race.cat.endsWith("Liège")).toList("race", bool) == @[false, true]
    check df.select(col.race.cat.slice(0, 5)).toList("race", string) == @["Ronde", "Liège"]

  test "files keep categories":
    let df = newDataFrame:
      medal: [Silver, Gold]
    let p = getTempDir() / "nanuq_medals.parquet"
    df.writeParquet(p)
    check readParquet(p).dtype("medal") == Medal
    let a = getTempDir() / "nanuq_medals.arrow"
    df.writeIpc(a)
    check readIpc(a).toList("medal", Medal) == @[Silver, Gold]

  test "inspection":
    let df = newDataFrame:
      medal: [Silver, Gold]
    check "$ medal <enum> Silver, Gold" in df.glimpse
    check df.describe.width == 2
    check df.describe.toList("medal", Option[string])[4].isNone   # no min, as in Python
