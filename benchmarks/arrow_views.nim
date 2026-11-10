## Copy vs zero-copy: reading a Polars column from Nim.
##
## Run: nim r -d:release benchmarks/arrow_views.nim [n]
import std/[monotimes, times, os, strutils, strformat, math]
import nanuq

let n = if paramCount() > 0: parseInt(paramStr(1)) else: 10_000_000
var xs = newSeq[float](n)
for i in 0 ..< n: xs[i] = float(i mod 1000) * 0.5
let df = newDataFrame(series("x", xs))
let s = df.getColumn("x")

proc report(label: string, ns: int64) =
  echo &"{label:<44} {ns.float / 1e6:9.2f} ms"

template bench(label: string, body: untyped) =
  var best = high(int64)
  for _ in 1 .. 5:
    let t = getMonoTime()
    body
    best = min(best, (getMonoTime() - t).inNanoseconds)
  report(label, best)

var acc = 0.0
echo &"{n} Float64 values"
bench("Polars: df.select(col.x.sum)"): acc += df.select(col("x").sum).toList("x", float)[0]
bench("copy: s.toList(float), then sum"): acc += sum(s.toList(float))
bench("zero-copy: s.view(float), then sum"): acc += sum(s.view(float).toOpenArray)
bench("zero-copy: s.toArrow (export only)"): acc += s.toArrow.array.length.float
bench("copy in: series(\"x\", seq) from Nim"): acc += series("x", xs).len.float
bench("mapElements(x * 2), view in, seq out"):
  acc += df.select(col("x").mapElements(proc (x: float): float = x * 2)).height.float
echo acc > 0
