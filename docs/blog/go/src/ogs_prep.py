"""Run the post's own OGS query (cells s07_schema and s08_query of go.py) on the full
2.8M-game sample and sink it to data/ogs_games.parquet with the streaming engine.
Usage, from the draft folder: python3 -I src/ogs_prep.py /tmp/godata/ogs/ogs_5pct.ndjson"""
import re, sys, time
import polars as pl
src = open("go.py").read()
cells = {re.match(r"\n# id: (\S+)", c).group(1): c for c in src.split("\n# %%")[1:] if not c.startswith(" [markdown]")}
ns = {"pl": pl}
for cid in ["s07_schema", "s08_query"]:
    exec(cells[cid].replace("data/ogs_slice.ndjson", sys.argv[1]), ns)
t = time.time()
ns["ogs"].sink_parquet("/tmp/ogs_games_full.parquet", engine="streaming")
print(f"{time.time() - t:.0f} s")
# What ships with the post: every fifth game (a 1% sample of OGS), fewer digits, and the
# first moves only for the even 19x19 games that section 12 looks at.
(pl.scan_parquet("/tmp/ogs_games_full.parquet").gather_every(5).select(
    "size", "handicap", "komi", "speed", "winner",
    started=pl.col("started").dt.date(),
    black_rank=pl.col("black_rank").round(1).cast(pl.Float32),
    white_rank=pl.col("white_rank").round(1).cast(pl.Float32),
    n_moves=pl.col("n_moves").cast(pl.UInt16),
    moves=pl.when((pl.col("size") == 19) & (pl.col("handicap") == 0)).then("moves"),
).sink_parquet("data/ogs_games.parquet", compression="zstd", compression_level=19))
print(pl.scan_parquet("data/ogs_games.parquet").select(pl.len()).collect())
# memory: see /home/user/scratch/memtest.py in the session; on 1 Nov 2026 (4-core, 15 GB VM)
# streaming sink 75 s, 0.13 GB anonymous memory; in-memory collect 89 s, 11.8 GB
