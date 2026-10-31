import std/[unittest, options, algorithm]
import nanuq

proc bears(): DataFrame =
  newDataFrame(series("id", [1, 2, 3]), series("name", ["Nanuq", "Ursa", "Tulok"]))

proc sightings(): DataFrame =
  newDataFrame(series("id", [3, 1, 1, 4]), series("place", ["Svalbard", "Churchill", "Kaktovik", "Wrangel"]))

proc sortedInts(df: DataFrame, c: string): seq[int] = df.toList(c, int).sorted

suite "joins":
  test "inner join on a column name":
    let j = bears().join(sightings(), on = ["id"])
    check j.columns == @["id", "name", "place"]
    check j.sortedInts("id") == @[1, 1, 3]

  test "every keyed join type":
    let (a, b) = (bears(), sightings())
    check a.join(b, on = ["id"], how = Left).height == 4       # 1 twice, 2 with null, 3
    check a.join(b, on = ["id"], how = Right).height == 4      # 3, 1, 1, 4 with null
    check a.join(b, on = ["id"], how = Full).height == 5
    let semi = a.join(b, on = ["id"], how = Semi)
    check semi.columns == @["id", "name"]
    check semi.sortedInts("id") == @[1, 3]
    check a.join(b, on = ["id"], how = Anti).toList("id", int) == @[2]

  test "left join keeps unmatched rows with nulls":
    let j = bears().join(sightings(), on = ["id"], how = Left, maintainOrder = Left)
    check j.toList("id", int) == @[1, 1, 2, 3]
    check j.toList("place", Option[string])[2] == none(string)

  test "expression keys and different names":
    let st = newDataFrame(series("station_id", [2, 3]), series("lat", [71.0, 78.2]))
    let byName = bears().join(st, leftOn = ["id"], rightOn = ["station_id"])
    let byExpr = bears().join(st, leftOn = [col("id")], rightOn = [col("station_id")])
    check byName.sortedInts("id") == @[2, 3]
    check byExpr.sortedInts("id") == @[2, 3]
    let onExpr = bears().join(sightings(), on = [col("id")])
    check onExpr.height == 3

  test "cross join":
    let sizes = newDataFrame(series("size", ["S", "L"]))
    let j = bears().join(sizes, how = Cross)
    check j.height == 6
    check j.columns == @["id", "name", "size"]

  test "missing or misplaced keys raise":
    expect NanuqError: discard bears().join(sightings(), how = Inner)
    expect NanuqError: discard bears().join(sightings(), leftOn = ["id"], rightOn = newSeq[string]())
    expect NanuqError: discard bears().join(sightings(), on = ["id"], how = Cross)

  test "suffix for clashing names":
    let other = newDataFrame(series("id", [1]), series("name", ["Big"]))
    check bears().join(other, on = ["id"]).columns == @["id", "name", "name_right"]
    check bears().join(other, on = ["id"], suffix = "_b").columns == @["id", "name", "name_b"]

  test "validate":
    expect NanuqError: discard bears().join(sightings(), on = ["id"], validate = OneToOne)
    check bears().join(sightings(), on = ["id"], validate = OneToMany).height == 3

  test "nullsEqual":
    let a = newDataFrame(series("k", [some(1), none(int)]), series("x", [1, 2]))
    let b = newDataFrame(series("k", [some(1), none(int)]), series("y", [3, 4]))
    check a.join(b, on = ["k"]).height == 1
    check a.join(b, on = ["k"], nullsEqual = true).height == 2

  test "coalesce":
    let (a, b) = (bears(), sightings())
    check a.join(b, on = ["id"], how = Full).columns == @["id", "name", "id_right", "place"]
    check a.join(b, on = ["id"], how = Full, coalesce = some(true)).columns ==
      @["id", "name", "place"]
    check a.join(b, on = ["id"], coalesce = some(false)).columns ==
      @["id", "name", "id_right", "place"]

  test "maintainOrder":
    let j = sightings().join(bears(), on = ["id"], how = Left, maintainOrder = Left)
    check j.toList("id", int) == @[3, 1, 1, 4]
    check j.toList("name", Option[string]) == @[some("Tulok"), some("Nanuq"), some("Nanuq"), none(string)]

  test "lazy join":
    let j = bears().lazy.join(sightings().lazy, on = ["id"], how = Anti)
    check j.collectSchema.len == 2
    check j.collect.toList("id", int) == @[2]

suite "concatenation":
  test "vertical":
    let c = concat([bears(), bears()])
    check c.height == 6
    check c.toList("id", int) == @[1, 2, 3, 1, 2, 3]

  test "vertical needs equal dtypes, relaxed finds a supertype":
    let i = newDataFrame(series("x", [1]))
    let f = newDataFrame(series("x", [2.5]))
    expect NanuqError: discard concat([i, f])
    let r = concat([i, f], how = VerticalRelaxed)
    check r.dtype("x") == Float64
    check r.toList("x", float) == @[1.0, 2.5]

  test "horizontal":
    let c = concat([bears(), newDataFrame(series("age", [5, 7, 9]))], how = Horizontal)
    check c.columns == @["id", "name", "age"]

  test "diagonal fills missing columns with nulls":
    let a = newDataFrame(series("id", [1]), series("name", ["Nanuq"]))
    let b = newDataFrame(series("id", [2]), series("weight", [450.0]))
    let c = concat([a, b], how = Diagonal)
    check c.columns == @["id", "name", "weight"]
    check c.toList("name", Option[string]) == @[some("Nanuq"), none(string)]
    check c.toList("weight", Option[float]) == @[none(float), some(450.0)]
    let d = newDataFrame(series("id", [3.5]))
    expect NanuqError: discard concat([a, d], how = Diagonal)
    check concat([a, d], how = DiagonalRelaxed).dtype("id") == Float64

  test "empty list raises":
    expect NanuqError: discard concat(newSeq[DataFrame]())
    expect NanuqError: discard concat(newSeq[LazyFrame]()).collect

  test "lazy concat":
    check concat([bears().lazy, bears().lazy]).collect.height == 6

suite "option values":
  test "bare values in typed contexts, even when repeated":
    check compiles(bears().join(sightings(), on = ["id"], how = Left, maintainOrder = Left))
    check JoinType.Left != JoinType.Right
    check MaintainOrderJoin.Left == MaintainOrderJoin.Left
