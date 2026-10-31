import std/[unittest, options, strutils]
import nanuq

proc one(df: DataFrame, e: Expr): seq[Option[string]] =
  df.select(e.alias("r")).toList("r", Option[string])

suite "str namespace":
  let df = newDataFrame:
    s: ["Pogačar", "  Seixas ", nil]

  test "case, length, reverse":
    check df.one(col.s.str.toUppercase) == @[some("POGAČAR"), some("  SEIXAS "), none(string)]
    check df.one(col.s.str.toLowercase)[0] == some("pogačar")
    check df.select(col.s.str.lenChars).toList("s", Option[int]) == @[some(7), some(9), none(int)]
    check df.select(col.s.str.lenBytes).toList("s", Option[int])[0] == some(8)
    check df.one(col.s.str.reverse)[0] == some("rač" & "agoP")

  test "strip":
    check df.one(col.s.str.stripChars)[1] == some("Seixas")
    check df.one(col.s.str.stripCharsStart)[1] == some("Seixas ")
    check df.one(col.s.str.stripCharsEnd)[1] == some("  Seixas")
    let w = newDataFrame(series("s", ["**win**"]))
    check w.one(col.s.str.stripChars("*")) == @[some("win")]
    check w.one(col.s.str.stripPrefix("**")) == @[some("win**")]
    check w.one(col.s.str.stripSuffix("**")) == @[some("**win")]

  test "matching":
    let r = newDataFrame(series("s", ["abc", "a.c", "xyz"]))
    proc b(e: Expr): seq[bool] = r.select(e.alias("r")).toList("r", bool)
    check b(col.s.str.contains(".")) == @[true, true, true]
    check b(col.s.str.contains(".", literal = true)) == @[false, true, false]
    check b(col.s.str.startsWith("a")) == @[true, true, false]
    check b(col.s.str.endsWith(col.s)) == @[true, true, true]
    check r.select(col.s.str.find("c")).toList("s", Option[int]) == @[some(2), some(2), none(int)]
    check r.select(col.s.str.countMatches("[ac]")).toList("s", int) == @[2, 2, 0]
    expect PolarsError:
      discard r.select(col.s.str.contains("("))
    check r.select(col.s.str.contains("(", strict = false)).toList("s", Option[bool]) ==
      @[none(bool), none(bool), none(bool)]

  test "extract":
    let t = newDataFrame(series("t", ["73h 56' 26\"", "73h"]))
    check t.one(col.t.str.extract(r"(\d+)'")) == @[some("56"), none(string)]
    check t.one(col.t.str.extract(r"(\d+)h", 0)) == @[some("73h"), some("73h")]

  test "replace":
    let b = newDataFrame(series("s", ["banana", "Paris–Nice"]))
    check b.one(col.s.str.replace("a", "o", n = 2))[0] == some("bonona")
    check b.one(col.s.str.replaceAll("a", "o"))[0] == some("bonono")
    check b.one(col.s.str.replaceAll("–", "-", literal = true))[1] == some("Paris-Nice")
    check b.one(col.s.str.replace(r"(\w+)–(\w+)", "$2 $1"))[1] == some("Nice Paris")

  test "slicing and padding":
    let n = newDataFrame(series("s", ["Pogačar"]), series("b", ["7"]))
    check n.one(col.s.str.slice(1, 2)) == @[some("og")]
    check n.one(col.s.str.slice(-3)) == @[some("čar")]
    check n.one(col.s.str.head(3)) == @[some("Pog")]
    check n.one(col.s.str.tail(2)) == @[some("ar")]
    check n.one(col.b.str.zfill(3)) == @[some("007")]
    check n.one(col.b.str.padStart(3, '.')) == @[some("..7")]
    check n.one(col.b.str.padEnd(3)) == @[some("7  ")]

  test "join":
    let w = newDataFrame:
      g: ["x", "y", "x"]
      r: ["a", nil, "b"]
    check w.one(col.r.str.join("|")) == @[some("a|b")]
    check w.one(col.r.str.join("|", ignoreNulls = false)) == @[none(string)]
    let per = w.groupBy(col.g).agg(col.r.str.join(", ")).sort("g").collect
    check per.toList("r", string) == @["a, b", ""]

suite "concatStr and format":
  let df = newDataFrame:
    rider: ["Vingegaard", nil]
    m: [4, 0]

  test "format":
    check df.one(format("{}: {}′", col.rider, col.m)) == @[some("Vingegaard: 4′"), none(string)]
    check df.one(format("x")) == @[some("x")]
    expect ValueError:
      discard format("{} {}", col.m)
    expect ValueError:
      discard format("{}", col.m, col.m)

  test "concatStr":
    check df.one(concatStr([col.rider, col.m], separator = "-")) == @[some("Vingegaard-4"), none(string)]
    check df.one(concatStr([col.rider, col.m], separator = "-", ignoreNulls = true)) ==
      @[some("Vingegaard-4"), some("0")]

  test "next to strutils":
    check "$1".format("x") == "x"
    check "{}" notin $format("{}!", col.m)
