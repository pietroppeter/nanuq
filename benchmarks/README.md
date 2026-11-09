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

Nanuq 0.6, same machine, best of 3: numeric columns without nulls are now read in place
through the Arrow C Data Interface (`view`), so the int → float callback takes 4.6-5.1 ms
(native 1.6-2.7 ms). Strings (52-62 ms) and struct rows (102-120 ms) still copy each
value into a Nim `string` or object.

## Copy vs view

`arrow_views.nim` reads a 10,000,000-value Float64 column from Nim in different ways:
Polars' own sum, a zero-copy `view`, a copy with `toList`, building a Series from a
`seq`, and `mapElements` (view in, `seq` out).

```sh
nim r -d:release benchmarks/arrow_views.nim
```

Linux sandbox (4 cores), Nanuq 0.6.1 prebuilt, best of 5, 2026-11-09:

| Reading the column | Time |
|---|---|
| Polars `sum` | 1.6 ms |
| `view`, Nim loop | 8.3 ms |
| `toList`, Nim loop | 63 ms |
| `series(name, seq)` | 61 ms |
| `mapElements(x * 2)` | 91 ms |

Used in the dev-log post "What about Arrow?".
