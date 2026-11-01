"""mapElements benchmark, Python side: py-polars map_elements vs native expressions.

Run: python3 benchmarks/map_elements.py [n]   (compare with map_elements.nim)
"""
import sys, time
import polars as pl

n = int(sys.argv[1]) if len(sys.argv) > 1 else 1_000_000
df = pl.DataFrame({
    "m": [4000 + i % 900 for i in range(n)],
    "peak": [f"Peak {i % 1000}" for i in range(n)],
})

def bench(name, expr, reps=3):
    best = float("inf")
    for _ in range(reps):
        t = time.perf_counter()
        df.select(expr)
        best = min(best, time.perf_counter() - t)
    print(f"{name:40s} {best * 1000:9.1f} ms")

print(f"py-polars {pl.__version__}, {n:,} rows")
bench("int: map_elements(x*3.28084)", pl.col.m.map_elements(lambda x: x * 3.28084, return_dtype=pl.Float64))
bench("int: native m*3.28084", pl.col.m * 3.28084)
bench("str: map_elements(len)", pl.col.peak.map_elements(lambda s: len(s), return_dtype=pl.Int64))
bench("str: native str.len_chars", pl.col.peak.str.len_chars())
bench("struct: map_elements(row)", pl.struct("peak", "m").map_elements(
    lambda r: r["m"] if r["peak"].endswith("7") else 0, return_dtype=pl.Int64))
bench("struct: native when/then",
      pl.when(pl.col.peak.str.ends_with("7")).then(pl.col.m).otherwise(0))
