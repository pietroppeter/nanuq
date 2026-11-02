"""Small inputs for the post: pro games (first 80 moves, plus full games for a subset),
Zobrist keys, the FIGG roll of Italian champions, the EGD player list."""
import csv, html, json, random, re, shutil, polars as pl
# pro games
full = pl.read_parquet("/tmp/godata/pro_full.parquet")
pl.read_parquet("/tmp/godata/pro_80.parquet").write_parquet("data/pro_games.parquet", compression="zstd", compression_level=19)
recent = full.filter(pl.col("file").str.starts_with("AlphaGo/") | (pl.col("DT").str.slice(0, 4) >= "2025"))
recent.write_parquet("data/pro_full_moves.parquet", compression="zstd", compression_level=19)
print("full subset", recent.shape)
# Zobrist keys: one random 64-bit number per point and colour (19*19*2)
rng = random.Random(19)
pl.DataFrame({"point": [p for p in range(361) for _ in (1, 2)],
              "color": ["B", "W"] * 361,
              "key": [rng.getrandbits(64) for _ in range(722)]},
             schema={"point": pl.UInt16, "color": pl.String, "key": pl.UInt64}).write_csv("data/zobrist.csv")
# champions
shutil.copy("/tmp/godata/raw/champions_raw.csv", "data/champions.csv")
# EGD list (fixed width), as downloaded; strip the HTML wrapper lines
txt = open("/tmp/godata/raw/allworld_lp.html", encoding="latin-1").read()
body = txt.split("</b>\n", 2)[2].split("</pre>")[0]
open("data/egd_players.txt", "w", encoding="utf-8").write(body)
print(body[:300])
