# %% [markdown]
# # Move 37
#
# *Nanuq 0.6 explainer, Python draft (py-polars 2.1). Every cell below will become a Nim
# block in the post, written against the 0.6 API. The outputs here are what the Nim
# version must print.*
#
# On 10 March 2016, in the second game of a five-game match in Seoul, the program AlphaGo
# played its 37th move on the fifth line from the right edge of the board, a shoulder hit
# that no strong human player would have chosen. Commentators thought it was a mistake.
# Lee Sedol, one of the best players of his generation, left the room for fifteen minutes.
# AlphaGo won that game, and the match 4 to 1, and the way people play go has not been the
# same since.
#
# Go is a board game for two players, older than chess, simple to state and very hard to
# master. Its games are also very good data: every game is a list of moves, every move a
# point on a grid, and players have been writing games down for four hundred years.
# Online servers record millions more every year.
#
# That makes go a nice playground for what is new in Nanuq 0.6, which is about how
# queries run and how data gets in and out: **streaming** a file too big for memory and
# **sinking** the result to Parquet, **saving queries** to reuse them, exact **Decimal**
# numbers, **Binary** columns and **bitwise** operations, fast **Nim callbacks** on Arrow
# data, **databases** and **Excel** files, and **testing helpers** to check that two
# frames agree.
#
# The story has four parts. First, 98,000 games played by Japanese professionals from
# the seventeenth century to last month. Then 2.8 million games played by amateurs on
# the Online Go Server. Then a tiny go engine, written as a callback. And last, a look at
# the champions of Italian go.
#
# Data, all public, downloaded on 1 November 2026: Andries Brouwer's database of
# professional games (homepages.cwi.nl/~aeb/go/games); the dump of all public games on
# online-go.com put together by Zachary Vance with OGS's permission (za3k.com/ogs); the
# roll of honour of the Italian Go Federation (figg.org); the player list of the European
# Go Database (europeangodatabase.eu).

# %%
# id: setup
import polars as pl

pl.Config(tbl_rows=12, tbl_cols=10, tbl_width_chars=120, fmt_str_lengths=40, float_precision=3);

import sys; sys.path.insert(0, "src")
import figs  # Plotly charts and boards; the Nim post redoes them with nim-plotly

# %% [markdown]
# ## Part 1: Ninety-eight thousand professional games
#
# ## 1. The board, the stones, the rules
#
# Go is played on a grid of 19 by 19 lines. Black and White take turns placing one stone
# on an empty intersection; stones never move after that. Stones of the same colour that
# touch along the lines form a group, and a group whose last empty neighbouring point
# (its last *liberty*) is filled by the opponent is captured and taken off the board. At
# the end, each player counts the area they surround. Black moves first, which is an
# advantage, so White gets a few points of compensation, called *komi*.
#
# Games are written down in SGF, a plain-text format where a move is two letters, the
# column and the row, from `a` (left, top) to `s` (right, bottom). `pd` is the fourth
# point from the right and the fourth from the top. Our database packs the moves of each
# game into one **Binary** value, two bytes per move. Binary columns are new in 0.6.
#
# What is in it: the SGF letters themselves, one byte each, so `pd` is the two bytes 112
# and 100. A String column would have worked just as well; we use Binary to try out the
# new type. It does fit the job: move *n* always sits at bytes 2*n* and 2*n*+1, `bin.get`
# hands back a byte as a number (`a` is 97, so a column is the byte minus 97), and
# looking for an opening is a prefix match on bytes.

# %%
# id: s01_read
pro = pl.read_parquet("data/pro_games.parquet")
pro.select("file", "DT", "PB", "PW", "KM", "RE", "moves").glimpse(max_items_per_column=2)

# %% [markdown]
# To draw a game we turn the bytes into points. `bin.size` tells how many bytes there
# are; the bytes come out one by one with `bin.get`. Here are the first 37 moves of the
# second game between AlphaGo (Black) and Lee Sedol (White).

# %%
# id: s01_points
game2 = pro.filter(pl.col("file") == "AlphaGo/LeeSedol/2.sgf")
first37 = (
    game2.select(pl.int_range(0, 37).alias("move"), pl.col("moves").first())
    .select(
        move=pl.col("move") + 1,
        color=pl.when(pl.col("move") % 2 == 0).then(pl.lit("B")).otherwise(pl.lit("W")),
        x=pl.col("moves").bin.get(pl.col("move") * 2).cast(pl.Int64) - 97,
        y=pl.col("moves").bin.get(pl.col("move") * 2 + 1).cast(pl.Int64) - 97,
    )
)
first37.tail(4)

# %%
# id: fig_move37
figs.board(first37, "AlphaGo vs Lee Sedol, game 2, moves 1 to 37",
           labels=first37.select("x", "y", text=pl.col("move").cast(pl.String),
                                 fg=pl.when(pl.col("color") == "B").then(pl.lit("white")).otherwise(pl.lit("black"))))

# %% [markdown]
# Move 37 is the black stone at P10, alone in the middle of the right side. Moves near the
# edge, on the third line, take territory; moves on the fourth line build influence
# towards the centre. A stone on the fifth line, this early, gives White an easy third
# line underneath. Michael Redmond, commentating in English, called it "a very surprising
# move". Fan Hui, who had lost to AlphaGo five months earlier: "It's not a human move.
# I've never seen a human play this move."
#
# ## 2. Komi, exactly
#
# How many points should White get for moving second? Go has argued about it for a
# century. Old Japanese games have no komi at all; komi appeared in the 1930s, and
# professionals went from 4.5 to 5.5, 6.5 and in China 7.5 points. The half point is there
# so that a game cannot end in a tie.
#
# Half points are exactly the kind of number that floating point gets almost right.
# **Decimal** columns, new in 0.6, store them exactly: `str.to_decimal(scale=1)` reads
# the `KM` property as a number with one digit after the point.

# %%
# id: s02_komi
games = (
    pro.filter(pl.col("SZ").is_null() | (pl.col("SZ") == "19"), pl.col("HA").is_null())
    .with_columns(
        year=pl.col("DT").str.extract(r"^(\d{4})").cast(pl.Int64),
        komi=pl.col("KM").str.strip_chars().str.to_decimal(scale=1),
        winner=pl.col("RE").str.extract(r"^([BW])\+"),
        margin=pl.col("RE").str.extract(r"^[BW]\+(\d+(?:\.\d)?)$").str.to_decimal(scale=1),
    )
)
games.group_by(decade=pl.col("year") // 10 * 10).agg(
    games=pl.len(), usual_komi=pl.col("komi").mode().first()
).filter(pl.col("decade") >= 1920).sort("decade")

# %% [markdown]
# Did it work? With komi 0, Black won 58% of the decisive games. Each extra point of
# komi took away about two and a half points of percentage, and at 6.5 the game is a
# coin toss: 50.2%.

# %%
# id: s02_fair
fair = (
    games.filter(pl.col("winner").is_not_null())
    .group_by("komi")
    .agg(games=pl.len(), black_wins=(pl.col("winner") == "B").mean())
    .filter(pl.col("games") >= 300, pl.col("komi").is_not_null())
    .sort("komi")
)
fair

# %%
# id: fig_komi
figs.bars(fair.with_columns(label=pl.col("komi").cast(pl.String)), "label", "black_wins",
          "How often Black wins, by komi (professional games, no handicap)", "Black wins",
          text=None, yformat=".0%")

# %% [markdown]
# A whole-number komi such as 5 can end in a draw, called *jigo*. Decimals make the
# test exact: a komi is whole when `komi == komi.floor()`, and the margins of half-point komi
# games always end in `.5`.

# %%
# id: s02_jigo
games.filter(pl.col("komi").is_not_null()).group_by(
    whole_komi=pl.col("komi") == pl.col("komi").floor()
).agg(
    games=pl.len(),
    draws=(pl.col("RE") == "Jigo").sum(),
    half_point_wins=(pl.col("margin") == pl.lit("0.5").str.to_decimal(scale=1)).sum(),
).sort("whole_komi")

# %% [markdown]
# ## 3. Where the first stone goes
#
# The board has eight symmetries (four rotations, each with a mirror image), so the
# opening move at `pd` and the one at `dp` are the same move. We fold every first move
# into one corner by counting lines from the nearest edge: a stone on the third line from
# one edge and the fourth from the other is a *3-4 point*, the classic *komoku*; the
# *4-4 point* is *hoshi*, a star point.

# %%
# id: s03_first
def line_from_edge(byte):
    v = pl.col("moves").bin.get(byte).cast(pl.Int64) - 97 + 1
    return pl.min_horizontal(v, 20 - v)

first = (
    games.filter(pl.col("moves").bin.size() >= 2, pl.col("year").is_not_null())
    .with_columns(a=line_from_edge(0), b=line_from_edge(1))
    .with_columns(
        point=pl.format("{}-{}", pl.min_horizontal("a", "b"), pl.max_horizontal("a", "b")),
        era=pl.when(pl.col("year") <= 1867).then(pl.lit("1: Edo, to 1867"))
        .when(pl.col("year") <= 1945).then(pl.lit("2: 1868-1945"))
        .when(pl.col("year") <= 1990).then(pl.lit("3: 1946-1990"))
        .when(pl.col("year") <= 2016).then(pl.lit("4: 1991-2016"))
        .otherwise(pl.lit("5: AI era, 2017-")),
    )
)
first.group_by("era", "point").len().with_columns(
    share=pl.col("len") / pl.col("len").sum().over("era")
).filter(pl.col("share") > 0.02).sort("era", "share", descending=[False, True])

# %% [markdown]
# In the Edo period nearly nine games in ten opened on a 3-4 point. The 4-4 point took
# over in the twentieth century, with the "New Opening" of Go Seigen and Kitani Minoru in
# the 1930s and, later, with komi: a fast, open style pays when Black has points to give
# back.

# %%
# id: fig_first
freq = (
    first.with_columns(
        x=pl.col("moves").bin.get(0).cast(pl.Int64) - 97,
        y=pl.col("moves").bin.get(1).cast(pl.Int64) - 97,
        panel=pl.col("era").str.slice(3),
    )
    .group_by("panel", "x", "y").len()
    .with_columns(share=pl.col("len") / pl.col("len").sum().over("panel"))
)
figs.heat_boards(freq, ["Edo, to 1867", "1868-1945", "1946-1990", "1991-2016", "AI era, 2017-"],
                 "Where Black puts the first stone")

# %% [markdown]
# The heatmaps also show a habit: Black's first stone goes in the top-right corner, from
# Black's point of view. It is a courtesy, leaving the corner nearest to the opponent's
# right hand free.
#
# ## 4. Searching the moves
#
# A Binary column can be searched without decoding it. `bin.starts_with` finds games by
# their first moves, `bin.slice` cuts out a few bytes, and `bin.encode` shows bytes as
# hexadecimal text (`70 64` is `p d`). Before AlphaGo, the most common start was Black
# at `pd` and White at `dd`, the two top corners; since 2017 it is `pd` and `dp`.

# %%
# id: s04_search
games.filter(pl.col("moves").bin.size() >= 4, pl.col("year").is_not_null()).group_by(
    after_alphago=pl.col("year") >= 2017
).agg(
    games=pl.len(),
    start_pd=pl.col("moves").bin.starts_with(b"pd").mean(),
    start_pddp=pl.col("moves").bin.starts_with(b"pddp").mean(),
    common_start=pl.col("moves").bin.slice(0, 4).mode().first(),
    as_hex=pl.col("moves").bin.slice(0, 4).bin.encode("hex").mode().first(),
).sort("after_alphago")

# %% [markdown]
# ## 5. The 3-3 invasion
#
# The clearest trace AlphaGo left on human play is in the corners. When one side holds a
# 4-4 point, the other can slide in underneath at the 3-3 point and live in the corner.
# Textbooks said this was fine *late* in the game, but giving the opponent a wall this
# early was bad style. AlphaGo did it at once, and won. Within a year everybody did.
#
# We write the test as one expression: a game has an early 3-3 invasion if, in its first
# twelve moves, some corner has both its 4-4 point and the 3-3 point beneath it. Moves come
# out of the Binary column as a list of two-letter strings.

# %%
# id: s05_invasion
moves12 = pl.col("moves").bin.slice(0, 24).cast(pl.String).str.extract_all("..")
early_33 = pl.any_horizontal(
    moves12.list.contains(hoshi) & moves12.list.contains(san_san)
    for hoshi, san_san in [("dd", "cc"), ("pd", "qc"), ("dp", "cq"), ("pp", "qq")]
).alias("early_33")
invasions = (
    games.filter(pl.col("year") >= 1990)
    .group_by("year")
    .agg(games=pl.len(), early_33=early_33.mean())
    .sort("year")
)
invasions.tail(13)

# %% [markdown]
# Between 1990 and 2017, a bit more than a game in five had an early 3-3 point next to a
# star point (some were the old, slow kind of invasion, or a 3-3 point played first). In
# 2018, a year after AlphaGo's 60 online wins against top professionals, it jumped to
# almost a game in two, and it stayed there.

# %%
# id: fig_invasion
figs.lines(invasions, "year", [("early_33", "early 3-3 invasions", "#b4462b")],
           "Professional games with a 3-3 invasion in the first 12 moves", "share of games",
           events=[(2016.2, "AlphaGo-Lee Sedol"), (2017.0, "AlphaGo Master online")], yformat=".0%")

# %% [markdown]
# We will want the same yardstick for amateurs in Part 2. Expressions can now be
# **serialized**: `meta.serialize` turns one into JSON (or a compact binary form), and
# `pl.Expr.deserialize` brings it back, in another script or another language. We save
# `early_33` to a file.

# %%
# id: s05_save
open("early_33.json", "w").write(early_33.meta.serialize(format="json"))
pl.Expr.deserialize("early_33.json", format="json").meta.output_name()

# %% [markdown]
# ## 6. Same position, different order
#
# Players reach the same opening position along different move orders. To find them,
# go programs give every position a *Zobrist hash*: draw one random 64-bit number for each
# point and colour, and XOR together the numbers of the stones on the board. XOR is
# commutative, so the order of moves doesn't matter, and two different positions almost
# never get the same hash. (A capture would XOR a stone away again; there are none this
# early.)
#
# **Bitwise** operations are new in 0.6. `bitwise_xor` is an aggregation, so the hash of
# each game's first ten moves is a `group_by`.

# %%
# id: s06_zobrist
keys = pl.read_csv("data/zobrist.csv", schema_overrides={"point": pl.Int64, "key": pl.UInt64})
openings = (
    games.filter(pl.col("moves").bin.size() >= 20, pl.col("year") >= 1990)
    .select("file", "year", mv=pl.col("moves").bin.slice(0, 20).cast(pl.String).str.extract_all(".."))
    .with_columns(color=pl.lit(["B", "W"] * 5))
    .explode("mv", "color")
    .with_columns(point=(pl.col("mv").str.slice(1, 1).str.to_integer(base=36) - 10) * 19
                  + pl.col("mv").str.slice(0, 1).str.to_integer(base=36) - 10)
    .join(keys, on=["point", "color"], maintain_order="left")
    .group_by("file", "year")
    .agg(zobrist=pl.col("key").bitwise_xor(), order=pl.col("mv").str.join(""))
)
openings.sort("file").head(3)

# %% [markdown]
# Grouping by the hash shows the most played positions after ten moves since 1990, and
# how many different move orders led to each.

# %%
# id: s06_top
top = (
    openings.group_by("zobrist")
    .agg(games=pl.len(), orders=pl.col("order").n_unique(), example=pl.col("order").mode().first(),
         first_year=pl.col("year").min(), last_year=pl.col("year").max())
    .sort("games", descending=True)
    .head(5)
)
top.with_columns(hash=pl.col("zobrist").cast(pl.String)).drop("zobrist")

# %% [markdown]
# Good keys are random bits. `bitwise_count_ones` counts the bits set to 1 (we expect
# about half of 64), `bitwise_leading_zeros` counts the zero bits at the front, and the
# aggregations `bitwise_and` and `bitwise_or` keep the bits that are set in all keys, or in
# any key.

# %%
# id: s06_bits
keys.select(
    mean_ones=pl.col("key").bitwise_count_ones().mean(),
    min_ones=pl.col("key").bitwise_count_ones().min(),
    max_ones=pl.col("key").bitwise_count_ones().max(),
    leading_zeros_max=pl.col("key").bitwise_leading_zeros().max(),
    all_and=pl.col("key").bitwise_and(),
    all_or_ones=pl.col("key").bitwise_or().bitwise_count_ones(),
)

# %% [markdown]
# ## Part 2: Two point eight million amateur games
#
# ## 7. A file too big to read
#
# The Online Go Server (OGS) has been running since 2005. Its complete public record, 56
# million games up to May 2025, comes as a single 46 GB gzipped file with one JSON object
# per line: 200 GB once unpacked, far more than the memory of a laptop. We streamed it
# once over the network and kept every twentieth line: **2,820,649 games** in a 10.3 GB
# NDJSON file. That is still too big to read comfortably, which is the point.
#
# The post ships the first 2,000 lines of that file, so every cell below runs. Each line
# is the raw API record of one game: players with their ranks, board size, komi, rules,
# clock settings, the outcome and the moves.
#
# Let Polars guess the types, and it gives up: the same field holds a boolean on one line
# and a number on another.

# %%
# id: s07_guess
try:
    pl.read_ndjson("data/ogs_slice.ndjson")
except pl.exceptions.ComputeError as e:
    print("read failed:", str(e).split("'")[0].strip(), "...")

# %% [markdown]
# So we say what we want, as a schema, and leave the rest out. The other fields, more
# than a hundred, are never even parsed. `ignore_errors` turns the few values that don't
# fit into nulls.

# %%
# id: s07_schema
player = pl.Struct({"username": pl.String, "rank": pl.Float64, "professional": pl.Boolean})
schema = {
    "game_id": pl.Int64, "start_time": pl.Int64, "width": pl.Int64, "height": pl.Int64,
    "handicap": pl.Int64, "komi": pl.Float64, "rules": pl.String, "outcome": pl.String,
    "winner": pl.Int64, "black_player_id": pl.Int64,
    "players": pl.Struct({"black": player, "white": player}),
    "time_control": pl.Struct({"speed": pl.String}),
    "moves": pl.List(pl.List(pl.Int64)),
}
raw = pl.scan_ndjson("data/ogs_slice.ndjson", schema=schema, ignore_errors=True)
raw.head(3).collect()

# %% [markdown]
# ## 8. Streaming into Parquet
#
# Now the query: one row per game, with the start as a datetime, the board size, komi as
# a Decimal, the two ranks, the result, the number of moves, and the first twelve moves
# turned into the same two-letter Binary form as the professional games. OGS gives a
# move as `[x, y, milliseconds]`, and `[-1, -1, ...]` for a pass.
#
# OGS ranks are numbers: 30 is 1 dan, 29 is 1 kyu, 20 is 10 kyu. Kyu grades go down as
# players get stronger, from 30 kyu (a beginner) to 1 kyu; then dan grades go up, from 1
# to about 9 dan for amateurs.

# %%
# id: s08_query
letters = "abcdefghijklmnopqrstuvwxyz"
def sgf_letter(i):
    return pl.when(i >= 0).then(pl.lit(letters).str.slice(i, 1)).otherwise(pl.lit("t"))

ogs = raw.filter(pl.col("width") == pl.col("height")).select(
    "game_id",
    started=pl.from_epoch("start_time", time_unit="s"),
    size="width",
    handicap="handicap",
    komi=pl.col("komi").cast(pl.Decimal(10, 1)),
    rules=pl.col("rules").str.to_lowercase(),
    speed=pl.col("time_control").struct.field("speed"),
    black_rank=pl.col("players").struct.field("black").struct.field("rank"),
    white_rank=pl.col("players").struct.field("white").struct.field("rank"),
    outcome="outcome",
    winner=pl.when(pl.col("winner") == pl.col("black_player_id")).then(pl.lit("B"))
    .when(pl.col("winner").is_not_null()).then(pl.lit("W")),
    n_moves=pl.col("moves").list.len(),
    moves=pl.col("moves").list.head(12).list.eval(
        sgf_letter(pl.element().list.get(0)) + sgf_letter(pl.element().list.get(1))
    ).list.join("").cast(pl.Binary),
)
ogs.head(0).collect()

# %% [markdown]
# Nothing has run yet: `ogs` is a lazy query, and collecting zero rows of it only shows
# its columns. The new **streaming engine** runs it in
# batches, so memory stays flat however big the file is, and `sink_parquet` writes the
# result straight to disk without ever building the whole table. On the 10.3 GB file
# (on a 4-core machine with 15 GB of memory) the streaming run took 75 seconds and 0.13 GB
# of working memory. The same query collected in memory took 89 seconds and 11.8 GB.
# Here it is on the slice.

# %%
# id: s08_sink
ogs.sink_parquet("ogs_slice.parquet", engine="streaming")
pl.scan_parquet("ogs_slice.parquet").select(
    games=pl.len(), first=pl.col("started").min(), last=pl.col("started").max()
).collect()

# %% [markdown]
# Is the streamed result the same as an ordinary in-memory run? The new **testing
# helpers** answer with one line: `assert_frame_equal` raises an error that points at the
# first difference, and returns quietly when there is none.

# %%
# id: s08_check
from polars.testing import assert_frame_equal
assert_frame_equal(pl.read_parquet("ogs_slice.parquet"), ogs.collect(engine="in-memory"))
print("streaming and in-memory results agree")

# %% [markdown]
# ## 9. Growth, AlphaGo and the lockdowns
#
# The streamed table of all 2.8 million games is 80 MB of Parquet. To keep the post
# small we ship every fifth game of it: 563,622 games, a 1% sample of everything played on
# OGS. Two moments stand out in the number of games started each month: March 2016, the week AlphaGo beat
# Lee Sedol, and spring 2020, when half the world was told to stay home.

# %%
# id: s09_months
games_ogs = pl.read_parquet("data/ogs_games.parquet")
monthly = games_ogs.group_by(month=pl.col("started").dt.truncate("1mo").dt.date()).len().sort("month")
monthly.filter(pl.col("month").is_between(pl.date(2016, 1, 1), pl.date(2016, 6, 1))
               | pl.col("month").is_between(pl.date(2020, 1, 1), pl.date(2020, 6, 1)))

# %% [markdown]
# March 2016 had twice the games of February. The lockdowns of 2020 did more, and for
# longer: from March the number of games grew by half and stayed high all year.

# %%
# id: fig_months
figs.lines(monthly.with_columns(games=pl.col("len") * 100), "month",
           [("games", "games per month (estimated: 1% sample × 100)", "#8c5a2b")],
           "Games started on OGS each month", "games",
           events=[("2016-03-09", "AlphaGo-Lee Sedol"), ("2020-03-15", "lockdowns")], mode="lines")

# %% [markdown]
# ## 10. Small boards, fast games
#
# Online, half the games are on smaller boards: 9×9 games last ten minutes and teach the
# tactics, 13×13 is a step towards the full board. Most games are played live, the rest by
# correspondence, a move a day.

# %%
# id: s10_sizes
games_ogs.filter(pl.col("size").is_in([9, 13, 19])).group_by("size").agg(
    games=pl.len(),
    share=pl.len() / games_ogs.height,
    median_moves=pl.col("n_moves").median(),
    blitz_or_live=pl.col("speed").is_in(["blitz", "live"]).mean(),
).sort("size")

# %% [markdown]
# ## 11. Does the stronger player win?
#
# Ranks are supposed to predict results. We take even games (no handicap) on the full
# board that ended with a winner, and group them by the rank difference between the two
# players, rounded to whole grades.

# %%
# id: s11_gap
even = games_ogs.filter(
    pl.col("size") == 19, pl.col("handicap") == 0, pl.col("winner").is_not_null(),
    pl.col("n_moves") >= 20,
).with_columns(gap=(pl.col("black_rank") - pl.col("white_rank")).round().cast(pl.Int64))
stronger = (
    even.filter(pl.col("gap") != 0)
    .group_by(grades=pl.col("gap").abs())
    .agg(games=pl.len(),
         stronger_wins=((pl.col("gap") > 0) == (pl.col("winner") == "B")).mean())
    .filter(pl.col("grades") <= 9)
    .sort("grades")
)
stronger

# %% [markdown]
# One grade of difference gives the stronger player 58% of the games, four grades three
# games in four, and it levels off around 80%. Ranks on a server drift, players have off
# days, and the handicap system exists for a reason: in a handicap game, the weaker
# player starts with extra stones, one for each grade of difference.

# %%
# id: fig_gap
figs.lines(stronger, "grades", [("stronger_wins", "stronger player wins", "#2b6c8f")],
           "Even games on 19×19: how often the higher-ranked player wins", "share of games",
           yformat=".0%")

# %% [markdown]
# ## 12. Do amateurs play like AlphaGo?
#
# Back to the saved expression from section 5. We load `early_33` from its JSON file and
# run it on the amateur games: the same yardstick, not a copy of the code. Strong
# amateurs (dan grades, rank 30 and up) and weaker ones (kyu grades), year by year, for
# years with at least 50 such games.

# %%
# id: s12_amateurs
early_33_saved = pl.Expr.deserialize("early_33.json", format="json")
amateurs = (
    games_ogs.filter(pl.col("size") == 19, pl.col("handicap") == 0, pl.col("n_moves") >= 30)
    .with_columns(year=pl.col("started").dt.year(),
                  level=pl.when(pl.min_horizontal("black_rank", "white_rank") >= 30)
                  .then(pl.lit("dan")).otherwise(pl.lit("kyu")))
    .group_by("year", "level")
    .agg(games=pl.len(), early_33=early_33_saved.mean())
    .filter(pl.col("games") >= 50)
    .sort("year", "level")
)
side_by_side = amateurs.pivot("level", index="year", values="early_33").join(
    invasions.select("year", pro="early_33"), on="year", how="left").filter(pl.col("year") >= 2014)
side_by_side

# %% [markdown]
# Strong amateurs followed the professionals: under a third of their games before 2018,
# one in two from 2019. (2018 is missing because the sample has too few games between two
# dan players that year.) Kyu players had been playing early 3-3 points more than the
# professionals all along (it is the simple, safe way to take a corner) and drifted up
# slowly.

# %%
# id: fig_amateurs
figs.lines(side_by_side.filter(pl.col("year") <= 2024), "year",
           [("pro", "professionals", "#b4462b"), ("dan", "OGS, dan players", "#2b6c8f"),
            ("kyu", "OGS, kyu players", "#8fb3c9")],
           "Early 3-3 invasions: professionals and amateurs", "share of games",
           events=[(2016.2, "AlphaGo")], yformat=".0%")

# %% [markdown]
# ## Part 3: A go engine in a callback
#
# ## 13. Replaying the games
#
# The moves alone don't say what the board looks like at the end: stones get captured.
# To know, you have to play the game through, checking after every move whether a group
# has lost its last liberty. That is a loop with a flood fill inside, the kind of code no
# built-in expression covers, so it goes in a callback: a function called on each value.
#
# In Python this is `map_elements` with a function written in Python (it is in
# `src/goboard.py`, about forty lines), and it is slow, because Python runs the loop. In
# the Nim tab the same forty lines are Nim, compiled, and Nanuq 0.6 hands the bytes over
# through the Arrow C Data Interface without copying them.
#
# We replay the 3,997 complete games we kept (AlphaGo's, and all professional games
# since 2025) and count the stones left and the stones captured.

# %%
# id: s13_replay
import goboard

def final_counts(moves: bytes) -> dict:
    board, captured_by_black, captured_by_white = goboard.replay(moves)
    return {"black_stones": board.count(1), "white_stones": board.count(2),
            "captured": captured_by_black + captured_by_white}

full = pl.read_parquet("data/pro_full_moves.parquet")
replayed = full.with_columns(
    final=pl.col("moves").map_elements(final_counts, return_dtype=pl.Struct(
        {"black_stones": pl.Int64, "white_stones": pl.Int64, "captured": pl.Int64}))
).unnest("final")
replayed.select("file", "PB", "PW", "RE", n_moves=pl.col("moves").bin.size() // 2,
                black_stones="black_stones", white_stones="white_stones", captured="captured").sort(
    "captured", descending=True).head(5)

# %% [markdown]
# AlphaGo Zero playing itself leads the table: programs don't resign early, so their
# games go on until every last group is settled. On a laptop the Python callback takes
# about 3 seconds for these games, and the Nim one a few hundredths of a second. Here is
# the bloodiest game between humans, at the end.

# %%
# id: fig_bloodiest
bloodiest = replayed.filter(~pl.col("file").str.starts_with("AlphaGo/")).sort("captured", descending=True).head(1)
board_bytes = goboard.replay(bloodiest["moves"][0])[0]
final_stones = pl.DataFrame({"cell": list(board_bytes)}).with_row_index("p").filter(pl.col("cell") > 0).select(
    x=pl.col("p").cast(pl.Int64) % 19, y=pl.col("p").cast(pl.Int64) // 19,
    color=pl.when(pl.col("cell") == 1).then(pl.lit("B")).otherwise(pl.lit("W")))
figs.board(final_stones, f"{bloodiest['PB'][0]} (B) vs {bloodiest['PW'][0]} (W), {bloodiest['DT'][0]}: final position")

# %% [markdown]
# And a sanity check across all games: the more moves a game has, the more stones get
# captured, but the board never holds more than 361.

# %%
# id: s13_check
replayed.select(
    games=pl.len(),
    mean_moves=(pl.col("moves").bin.size() // 2).mean(),
    mean_captured=pl.col("captured").mean(),
    max_on_board=(pl.col("black_stones") + pl.col("white_stones")).max(),
    corr_moves_captured=pl.corr(pl.col("moves").bin.size(), pl.col("captured")),
)

# %% [markdown]
# ## Part 4: Italian go
#
# ## 14. Champions, in a database
#
# Italy has played go seriously since the 1970s. The Italian Go Federation (FIGG) has
# held a national championship every year since 1980; since 1992 the two best Italian
# players of the championship tournament meet in a final. The federation's roll of honour
# lists every winner, the score of the final and the runner-up. (2024 is missing from it;
# the 2025 result comes from the federation's news.)
#
# New in 0.6, frames go to and from **databases**: `write_database` creates a table,
# `read_database` runs a SQL query and returns a frame. Here we use SQLite, a database in
# a single file.

# %%
# id: s14_db
champions = pl.read_csv("data/champions.csv")
champions.write_database("champions", "sqlite:///italian_go.db", if_table_exists="replace")
titles = pl.read_database_uri(
    """
    SELECT winner AS player, COUNT(*) AS titles, MIN(year) AS first, MAX(year) AS last
    FROM champions GROUP BY winner ORDER BY titles DESC, first
    """,
    "sqlite://italian_go.db",
)
with pl.Config(tbl_rows=-1):  # all fourteen
    print(titles)

# %% [markdown]
# Fourteen champions in 45 championships, and the first six hold 34 titles between them.
# The finals are long-running rivalries: some pairs met again and again.

# %%
# id: s14_finals
pl.read_database_uri(
    """
    SELECT winner, runner_up, COUNT(*) AS finals, GROUP_CONCAT(year, ' ') AS years
    FROM champions WHERE runner_up IS NOT NULL AND runner_up <> ''
    GROUP BY winner, runner_up HAVING COUNT(*) >= 2 ORDER BY finals DESC
    """,
    "sqlite://italian_go.db",
)

# %% [markdown]
# ## 15. Fifty-six thousand players in a text file
#
# The European Go Database records every rated tournament game in Europe. Its player list
# is a plain text table with fixed-width columns: the PIN, the name (last name first),
# country, club, grade, a suggested promotion, the rating (GoR), the number of
# tournaments and the code of the last one (a letter, then the date as YYMMDD). We read each line as one string, keep the
# lines that start with a PIN, and cut them at fixed positions.

# %%
# id: s15_egd
lines = pl.read_csv("data/egd_players.txt", has_header=False, new_columns=["line"], separator="\x01").filter(
    pl.col("line").str.contains(r"^ \d{8} "))
def cut(start, length):
    return pl.col("line").str.slice(start, length).str.strip_chars()

egd = lines.select(
    pin=cut(0, 10).cast(pl.Int64),
    name=cut(11, 38).str.replace_all("_", " "),
    country=cut(49, 2),
    club=cut(53, 4),
    grade=cut(57, 6),
    gor=cut(68, 7).cast(pl.Int64),
    tournaments=cut(75, 6).cast(pl.Int64),
    last=cut(83, 8),
).with_columns(yy=pl.col("last").str.slice(1, 2).str.to_integer(strict=False)).with_columns(
    last_year=pl.when(pl.col("yy") > 50).then(1900 + pl.col("yy")).otherwise(2000 + pl.col("yy"))
).drop("yy")
egd.filter(pl.col("country") == "IT").sort("gor", descending=True).head(5)

# %% [markdown]
# How does Italy compare? Ratings work like chess Elo: 2100 is about 1 dan, and every 100
# points is one grade. Among players active in the last five years:

# %%
# id: s15_countries
egd.filter(pl.col("last_year") >= 2021).group_by("country").agg(
    players=pl.len(), dan=(pl.col("gor") >= 2050).sum(), median_gor=pl.col("gor").median(),
).filter(pl.col("players") >= 300).sort("players", descending=True).head(10)

# %% [markdown]
# ## 16. The champions today, in a spreadsheet
#
# Joining the roll of honour with the database gives each champion's current rating and
# the number of tournaments they have played: some won the title and then stopped, others
# are still playing forty years later. EGD writes names last name first, so we flip ours.

# %%
# id: s16_join
champion_cards = (
    titles.with_columns(name=pl.col("player").str.replace(r"^(\S+) (.+)$", "$2 $1"))
    .join(egd.filter(pl.col("country").is_in(["IT", "DE"])), on="name", how="left")
    .select("player", "titles", "first", "last", "grade", "gor", "tournaments", "last_year")
)
champion_cards

# %% [markdown]
# Spreadsheets are where results like this end up, so 0.6 also writes and reads **Excel**
# files. `write_excel` makes a real `.xlsx` with a header row and autofit columns, and
# `read_excel` reads a sheet back.

# %%
# id: s16_excel
champion_cards.write_excel("italian_champions.xlsx", worksheet="champions", autofit=True)
back = pl.read_excel("italian_champions.xlsx", sheet_name="champions")
assert_frame_equal(back, champion_cards, check_dtypes=False)
back.shape

# %% [markdown]
# ## Afterword
#
# Go players say that the board holds more positions than there are atoms in the
# universe; a laptop with Polars can still hold every game humans have played on it. In
# this post Nanuq streamed an 8 GB file it could not read at once, saved a query and used
# it again on other data, counted komi in exact half points, searched moves stored as
# bytes, hashed positions with XOR, replayed four thousand games in a Nim callback, and
# moved tables in and out of SQLite and Excel.
#
# AlphaGo retired in 2017. Its move 37 is still being played.
