import std/[unittest, options, tables]
import nanuq

suite "smaller functions":
  let df = newDataFrame:
    den: ["A", "A", "B"]
    kg: [410, 380, 500]

  test "expression functions":
    let r = df.select(col("kg").get(1).alias("second"), col("kg").upperBound.alias("max"))
    check r.toList("second", int)[0] == 380
    check df.select((col("kg") > 400).argTrue.alias("heavy")).toList("heavy", int) == @[0, 2]
    check df.select(col("kg").hash(1).alias("h")).dtype("h") == UInt64
    check df.select(col("kg").shuffle(seed = 1)).toList("kg", int) == df.select(col("kg").shuffle(seed = 1)).toList("kg", int)
    check df.select(col("kg").sample(2, seed = some(3))).height == 2
    check df.select(col("kg").extendConstant(0, 2)).toList("kg", int) == @[410, 380, 500, 0, 0]
    let rl = df.select(col("den").rle).unnest("den")
    check rl.toList("len", int) == @[2, 1]
    check df.select(col("kg").reshape([-1, 1])).dtype("kg") == Array(Int64, 1)

  test "over with mapping":
    let j = df.select(col("den"), col("kg").over("den", MappingStrategy.Join).alias("all"))
    check j.toList("all", seq[int]) == @[@[410, 380], @[410, 380], @[500]]

  test "names and meta":
    let e = (col("kg") * 2).alias("double")
    check e.meta.outputName == "double"
    check e.meta.rootNames == @["kg"]
    check col("*").meta.hasMultipleOutputs
    check col("a").meta.isColumn
    check lit(1).meta.isLiteral
    check e.meta.undoAliases.meta.outputName == "kg"
    expect PolarsError:
      discard col("*").meta.outputName
    check df.select(col("den").name.toUppercase).columns == @["DEN"]

  test "equals and stacking":
    let a = df.head(1)
    check a.equals(a)
    check not a.equals(df)
    let n = newDataFrame:
      x: [1, nil]
    check n.equals(n)
    check not n.equals(n, nullEqual = false)
    check df.vstack(df).height == 6
    check df.extend(df).height == 6
    check df.hstack([series("z", [1, 2, 3])]).columns == @["den", "kg", "z"]
    let other = newDataFrame:
      w: [1, 2, 3]
    check df.hstack(other).width == 3
    check df["kg"].equals(df["kg"])

  test "update, upsample, size, partitions, collectAll":
    let bears = newDataFrame:
      bear: ["Ada", "Bo"]
      kg: [410, 380]
    let fix = newDataFrame:
      bear: ["Bo"]
      kg: [395]
    check bears.update(fix, on = "bear").toList("kg", int) == @[410, 395]
    let t = newDataFrame:
      day: [date(2026, 3, 1), date(2026, 3, 4)]
      seen: [3, 1]
    let u = t.upsample("day", every = "1d")
    check u.height == 4
    check u.toList("seen", Option[int]) == @[some(3), none(int), none(int), some(1)]
    check bears.estimatedSize > 0
    let parts = df.partitionBy("den", asDict = true)
    check parts.len == 2
    check parts[@["B"]].height == 1
    let all = collectAll([df.lazy, bears.lazy])
    check all.len == 2 and all[1].height == 2
