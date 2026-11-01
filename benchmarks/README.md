# Benchmarks

Small, focused comparisons with py-polars. They are not run in CI.

## mapElements

`map_elements.nim` and `map_elements.py` run the same three user functions over a
1,000,000-row frame, and the native expression that does the same work:

```sh
nim r -d:release benchmarks/map_elements.nim
python3 benchmarks/map_elements.py
```

Linux sandbox (4-core Xeon), py-polars 2.1.0, Nanuq 0.5 with a local stable-Rust build,
best of 3, 2026-11-01:

| Workload | py-polars `map_elements` | Nanuq `mapElements` | native (both) |
|---|---|---|---|
| int → float (`x * 3.28084`) | 128-187 ms | 14-18 ms | 2-4 ms |
| string → int (`len`) | 106-128 ms | 50-74 ms | 5-9 ms |
| struct row → int | 328-383 ms | 90-123 ms | 7-9 ms |

Nanuq's callbacks are 2-10x faster than Python's, because the loop over the values is
compiled Nim. But they are still 5-12x slower than native expressions: each batch is
copied from Arrow memory into Nim seqs (one allocation per string) and the results are
copied back into a new Series. A native expression is the fast path in both languages.
