## toHtml against the HTML Python Polars' `_repr_html_` produced for the same
## data (fixtures in tests/data/*.html, written with Python Polars 2.1.0).
import std/[os, unittest, strutils, options]
import nanuq, nanuq/datasets

const dataDir = currentSourcePath.parentDir / "data"

proc expected(name: string): string = readFile(dataDir / name)

suite "toHtml":
  test "penguins, same as Python":
    check penguins().toHtml == expected("penguins.html")

  test "nulls, escaping, long strings and floats":
    let df = newDataFrame(
      series("a", [some 1, none int, some 3, some 1234567]),
      series("s", [some "<b>", some "x  y 'q' & z", some repeat('a', 40), none string]),
      series("f", [some 5076.016260162602, none float, some 1e-12, some 2.5]),
      series("b", [some true, none bool, some false, some true]),
    )
    check df.toHtml == expected("mixed.html")

  test "rows are cut to the first and last ones":
    var n = newSeq[int](1234)
    for i in 0 ..< n.len: n[i] = i
    check newDataFrame(series("n", n)).toHtml == expected("long.html")

  test "columns are cut to the first and last ones":
    var cols: seq[Series]
    for i in 0 ..< 80: cols.add series("c" & $i, [i])
    check newDataFrame(cols).toHtml == expected("wide.html")

  test "limits are parameters":
    let html = penguins().toHtml(maxRows = 4, maxCols = 2)
    check html.count("<tr>") == 2 + 5
    check "<th>species</th><th>&hellip;</th><th>year</th>" in html
