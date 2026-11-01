## mapElements benchmark, Nim side: Nanuq mapElements vs native expressions.
##
## Run: nim r -d:release benchmarks/map_elements.nim [n]   (compare with map_elements.py)
import std/[monotimes, times, os, strutils, strformat]
import nanuq

let n = if paramCount() > 0: parseInt(paramStr(1)) else: 1_000_000
var ms = newSeq[int](n)
var peaks = newSeq[string](n)
for i in 0 ..< n:
  ms[i] = 4000 + i mod 900
  peaks[i] = "Peak " & $(i mod 1000)
let df = newDataFrame(series("m", ms), series("peak", peaks))

proc bench(name: string, e: Expr, reps = 3) =
  var best = high(int64)
  for _ in 1 .. reps:
    let t = getMonoTime()
    discard df.select(e)
    best = min(best, (getMonoTime() - t).inNanoseconds)
  echo &"{name:<40} {best.float / 1e6:9.1f} ms"

type Row = object
  peak: string
  m: int

echo &"Nanuq, {n} rows"
bench("int: mapElements(x*3.28084)", col.m.mapElements(proc (x: int): float = x.float * 3.28084))
bench("int: native m*3.28084", col.m * 3.28084)
bench("str: mapElements(len)", col.peak.mapElements(proc (s: string): int = s.len))
bench("str: native str.lenChars", col.peak.str.lenChars)
bench("struct: mapElements(row)", asStruct("peak", "m").mapElements(proc (r: Row): int =
  (if r.peak.endsWith("7"): r.m else: 0)))
bench("struct: native when/then",
      `when`(col.peak.str.endsWith("7")).then(col.m).otherwise(0))
