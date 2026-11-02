"""Pack the 97k Japanese pro games (homepages.cwi.nl/~aeb/go/games/games.tgz, extracted to
/tmp/godata/cwi) into one Parquet file: SGF header fields as strings plus the main line of
moves as one Binary value (two SGF letters per move, "tt" or "" for a pass)."""
import glob, re, sys, polars as pl
root = sys.argv[1] if len(sys.argv) > 1 else "/tmp/godata/cwi"
out = sys.argv[2] if len(sys.argv) > 2 else "data/pro_games.parquet"
maxmoves = int(sys.argv[3]) if len(sys.argv) > 3 else 10_000
PROPS = ["DT", "PB", "PW", "BR", "WR", "KM", "HA", "RE", "SZ", "EV", "RU"]
rows = []
for f in sorted(glob.glob(f"{root}/**/*.sgf", recursive=True)):
    raw = open(f, "rb").read()
    try: s = raw.decode("utf-8")
    except UnicodeDecodeError: s = raw.decode("latin-1")
    head = s.split(";B[", 1)[0].split(";W[", 1)[0]
    r = {"file": f.split("/games/", 1)[-1]}
    for p in PROPS:
        m = re.search(rf"(?<![A-Z]){p}\[((?:[^\]\\]|\\.)*)\]", head)
        r[p] = m.group(1).strip() if m else None
    # main line only: stop at the first variation
    main = s.split("(;", 2)
    body = main[1] if len(main) > 1 else s
    body = body.split("(", 1)[0]
    mv = re.findall(r";\s*([BW])\[([a-s]{0,2})\]", body)
    r["moves"] = "".join((c if len(c) == 2 else "tt") for _, c in mv[:maxmoves]).encode()
    r["first_color"] = mv[0][0] if mv else None
    rows.append(r)
df = pl.DataFrame(rows, schema={"file": pl.String, **{p: pl.String for p in PROPS},
                                "moves": pl.Binary, "first_color": pl.String})
df.write_parquet(out, compression="zstd", compression_level=19)
print(df.shape, df.select(pl.col("moves").bin.size().sum()))
