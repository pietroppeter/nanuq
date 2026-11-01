# %% [markdown]
# # Above 4000
#
# *Nanuq 0.5 explainer, Python draft (py-polars 2.1). Every cell below will become a Nim
# block in the post, written against the 0.5 API. The outputs here are what the Nim
# version must print.*
#
# Mountain data is never flat. A summit has a height, but also a list of countries it
# sits on, a list of people who first stood on top, a parent peak, a col. A trek is a
# list of stages, each a list of paths, each a list of points, each a longitude, a
# latitude and an elevation. Wikipedia tables pack all of this into strings, and
# OpenStreetMap hands it out as JSON nested five levels deep.
#
# That makes mountains the perfect playground for what is new in Nanuq 0.5: **lists,
# arrays and structs**, splitting and decoding strings into them, **JSON** in and out,
# **SQL** queries, and **Nim callbacks** for the bits no built-in expression covers.
#
# The first part stays in the Alps: the 82 official summits above 4000 metres, and eight
# classic multi-day treks around them. The second part zooms out to the mountain ranges
# of the whole world and its fourteen peaks above 8000 metres.
#
# Data, all public, downloaded on 1 November 2026: the UIAA list of Alpine four-thousanders
# as published on English Wikipedia; summit coordinates from Wikidata and Camptocamp; hiking
# routes from OpenStreetMap through Waymarked Trails; elevations from the AWS Terrain Tiles;
# the GMBA Mountain Inventory v2 for the world's ranges; Wikidata for the 8000-metre peaks.

# %%
# id: setup
import math, os, tempfile
import polars as pl

pl.Config(tbl_rows=12, tbl_cols=10, tbl_width_chars=120, fmt_str_lengths=40, float_precision=1);

import sys; sys.path.insert(0, "src")
import figs  # Plotly charts and maps; the Nim post redoes them with nim-plotly

# %% [markdown]
# ## Part 1: The Alps
#
# ## 1. Eighty-two summits
#
# How many mountains in the Alps are higher than 4000 metres? It depends on what you call
# a mountain. Mont Blanc has a dozen bumps above 4000 m on its shoulders; is each one a
# summit? In 1994 the UIAA, the international federation of mountaineering clubs, settled
# it with an official list of **82 four-thousanders**, using a mix of topography (how far
# a peak rises above the col that joins it to a higher one) and mountaineering judgement.
#
# Wikipedia has the list as a table. We saved it as a CSV exactly as it comes, footnote
# markers and all.

# %%
# id: s01_raw
raw = pl.read_csv("data/uiaa_4000ers_raw.csv").filter(pl.col("Nr.").is_not_null())
raw.glimpse(max_items_per_column=3)

# %% [markdown]
# Every column after the height is a string with more than one thing inside. Country is
# a list of countries. Isolation (the distance to the nearest higher point) carries the
# name of that point. Prominence carries the name of the col. First ascent is a date
# followed by a list of people. Let's take them apart one at a time.
#
# ## 2. Countries: from a string to a list
#
# The Country column has slashes, spaces and footnotes: `France/ Italy [9]`,
# `France Italy`, `Italy/Switzerland`. We strip the footnotes, split on slashes and
# spaces, and drop the empty pieces. What comes back is a column of type
# `list[str]`.

# %%
# id: s02_countries
peaks = raw.select(
    nr=pl.col("Nr.").cast(pl.Int64),
    summit=pl.col("Summit").str.replace_all(r"\[.*?\]", ""),
    height=pl.col("Height (m)").cast(pl.Int64),
    range=pl.col("Range"),
    countries=pl.col("Country")
    .str.replace_all(r"\[\d+\]", "")
    .str.replace_all(r"[/ ]+", "/")
    .str.strip_chars("/")
    .str.split("/"),
    isolation=pl.col("Isolation[6] (km)"),
    prominence=pl.col("Prominence[6] (m)"),
    first_ascent=pl.col("First ascent[7]"),
)
peaks.select("summit", "height", "countries").head(8)

# %% [markdown]
# A list column can be measured with `list.len`, searched with `list.contains`, and
# turned back into rows with `explode`. Here is how many four-thousanders each country
# can claim, how many sit right on a border, and which countries share them (sorting and
# joining each list gives one label per combination).

# %%
# id: s02_per_country
print(peaks.explode("countries")["countries"].value_counts(sort=True))
print(peaks.select(on_a_border=(pl.col("countries").list.len() > 1).sum()))
print(peaks.group_by(pl.col("countries").list.sort().list.join(" + ")).len().sort(
    "len", "countries", descending=[True, False]
))

# %% [markdown]
# Switzerland has 48, Italy 38, France 26, which adds up to more than 82 because 30
# summits sit on a border: 17 between Italy and Switzerland, 13 between France and Italy.
# Only 13 are entirely French and 8 entirely Italian, against 31 entirely Swiss, and not
# a single one stands on the French-Swiss border. Mont Blanc is on the French-Italian
# one, and France and Italy have disagreed about exactly where that border runs over
# the top since the 18th century.
#
# ## 3. Prominence: from a string to a struct
#
# Prominence is how far a peak rises above the lowest col you must cross to reach
# anything higher. It is the number mountaineers use to tell a mountain from a bump on
# a ridge. The column packs the number and the name of that col into one string,
# `1,043  Col Durand`, and Isolation does the same with a distance and the nearest higher
# peak.
#
# `str.extract_groups` pulls both parts out at once into a **struct**: a single column
# whose values have named fields, like a small row inside a row. `struct.field` reads
# one field back, `unnest` spreads them all into columns.

# %%
# id: s03_structs
parts = peaks.select(
    "summit",
    "height",
    prom=pl.col("prominence").str.extract_groups(r"^(?<metres>[\d,]+)\s+(?<col>.*)$"),
    iso=pl.col("isolation").str.extract_groups(r"^(?<km>[\d.,]+)\s+(?<higher>.*)$"),
)
print(", ".join(f.name for f in parts.schema["prom"].fields))
parts.head(5)

# %% [markdown]
# Careful with the commas. Prominence uses them as thousands separators (`2,165`), and
# so does isolation, except that isolation also has decimals (`0.6`). A naive cast of
# Mont Blanc's isolation, `2,812`, as a decimal comma would put the nearest higher point
# 2.8 km away; it is Elbrus, in the Caucasus, 2812 km away. We drop the commas before
# casting.

# %%
# id: s03_prominence
peaks = peaks.with_columns(
    prom_m=pl.col("prominence").str.extract(r"^([\d,]+)").str.replace_all(",", "").cast(pl.Int64),
    col=pl.col("prominence").str.extract(r"^[\d,]+\s+(.*)$").str.replace_all(r"\s*\[.*?\]", ""),
    iso_km=pl.col("isolation").str.extract(r"^([\d.,]+)").str.replace_all(",", "").cast(pl.Float64),
    higher=pl.col("isolation").str.extract(r"^[\d.,]+\s+(.*)$"),
)
print(peaks.select(
    over_1000=(pl.col("prom_m") >= 1000).sum(),
    under_100=(pl.col("prom_m") < 100).sum(),
    under_30=(pl.col("prom_m") < 30).sum(),
))
peaks.top_k(8, by="prom_m").select("summit", "height", "prom_m", "col", "iso_km", "higher")

# %% [markdown]
# Only 12 of the 82 are mountains in their own right by the 1000-metre rule. Mont
# Blanc's prominence is its whole height above the lowest col on the way to anything
# taller, which is somewhere in the flatlands of Russia. Two in five (33) rise less than
# 100 metres above their col, six of them less than 30: shoulders and towers of bigger mountains,
# kept because climbers treat them as separate goals.
#
# ## 4. Who climbed them first
#
# The First ascent column is the messiest of all:
# `14 July 1865  Croz, Taugwalder, Whymper, Hudson, Douglas and Hadow`. We take the
# year with a regular expression, and turn the rest into a list of names by treating
# "and" (and the German "mit", which slipped into the English page) as commas.

# %%
# id: s04_ascents
ascents = peaks.select(
    "summit",
    "height",
    year=pl.col("first_ascent").str.extract(r"(\d{4})").cast(pl.Int32),
    party=pl.col("first_ascent")
    .str.replace(r"^.*?\d{4}(\[\d+\])?\s*", "")
    .str.replace_all(r"\[.*?\]|\(.*?\)|\".*?\"", "")
    .str.replace_all(r" (and|mit) ", ", ")
    .str.split(",")
    .list.eval(pl.element().str.strip_chars()),
)
ascents.head(6)

# %% [markdown]
# Explode the lists and count: who stood first on the most four-thousanders?

# %%
# id: s04_who
ascents.explode("party").drop_nulls("party")["party"].value_counts(sort=True).head(8)

# %% [markdown]
# Melchior Anderegg, a mountain guide from the Bernese Oberland, leads with six, ahead
# of Christian Almer, another Oberland guide, with five. Most of the famous names of the
# period show up with three or four: the British climbers Leslie Stephen, Horace Walker
# and Edward Whymper, the Chamonix guides Michel Croz and Michel-Clément Payot. And the
# list has its limits: when the page says "Jakob and Melchior Anderegg", our split gives
# a lone "Jakob". We fix that in section 9 with a Nim callback.
#
# When did all this happen? Group the years by decade.

# %%
# id: s04_decades
with pl.Config(tbl_rows=20):
    print(ascents.group_by((pl.col("year") // 10 * 10).alias("decade")).len().sort("decade"))
print(ascents.select(
    dated=pl.col("year").is_not_null().sum(),
    golden_age=pl.col("year").is_between(1854, 1865).sum(),
    first=pl.col("year").min(),
    last=pl.col("year").max(),
))

# %% [markdown]
# Mountaineers call the years from 1854 (the Wetterhorn) to 1865 (the Matterhorn) the
# **golden age of alpinism**. Of the 74 summits with a known year, 36 were first climbed
# in those twelve seasons. The very first was the Dôme du Goûter in 1784, two years before
# Mont Blanc itself; the last was the Grand Pilier d'Angle, climbed by Walter Bonatti and
# Toni Gobbi in 1957.
#
# ## 5. On the map
#
# The list has no coordinates, so we join them in from a separate file built from
# Wikidata and Camptocamp (see `src/peaks_prep.py`), on the list number.

# %%
# id: s05_join
coords = pl.read_csv("data/uiaa_coords.csv")
peaks = peaks.join(coords, on="nr", how="left", validate="1:1")
with pl.Config(float_precision=4):
    print(peaks.select("summit", "height", "lon", "lat", "source").head(5))

# %%
# id: fig_peaks
figs.alps_map(peaks)

# %% [markdown]
# All 82 fit in a strip about 250 km long, from the Barre des Écrins in the south-west to
# Piz Bernina in the east, and most crowd around two centres: the Mont Blanc massif and
# the Valais around Zermatt.
#
# ## 6. Eight treks, as JSON
#
# You don't need a rope to see these mountains up close. Several classic multi-day treks
# go around them, hut to hut: the Tour du Mont Blanc, the Tour du Cervin around the
# Matterhorn, the Tour Monte Rosa, the Tour des Combins, the Walker's Haute Route from
# Chamonix to Zermatt, and further south and east the Alta Via 1 of the Aosta Valley and
# the Alte Vie 1 and 2 of the Dolomites.
#
# OpenStreetMap volunteers have mapped all of them as *route relations*: a route made of
# stages, a stage made of ways (stretches of path), a way made of points. We downloaded
# each one from Waymarked Trails, sampled the terrain height at every point, and saved
# them as newline-delimited JSON, one trek per line, keeping the nesting
# (`src/treks_prep.py`). `read_ndjson` reads it into eight rows.

# %%
# id: s06_read
treks = pl.read_ndjson("data/treks.ndjson", infer_schema_length=None)
print(treks.shape)
print(", ".join(f.name for f in treks.schema["stages"].inner.fields))
treks.select("id", "name", n_stages=pl.col("stages").list.len())

# %% [markdown]
# Eight rows, but a lot inside them. The `stages` column is a list of structs; each
# stage struct holds a list of way structs; each way holds an OpenStreetMap `tags`
# struct and a list of points, each point a list of three numbers. How many tag fields?

# %%
# id: s06_tags
way_type = treks.schema["stages"].inner.fields[3].dtype.inner
tag_fields = [f.name for f in way_type.fields[3].dtype.fields]
print(len(tag_fields), ", ".join(sorted(tag_fields)[:12]))

# %% [markdown]
# 166 of them. Every way carries only the few tags someone bothered to map, and
# the struct holds the union of all of them, with nulls everywhere else.
#
# ## 7. Unnesting, level by level
#
# Two `explode`s and two `unnest`s turn eight treks into one row per way. On the way we
# give the long official names shorter labels.

# %%
# id: s07_ways
short = {
    "Tour du Mont Blanc - Itinéraire principal": "Tour du Mont Blanc",
    "Alta via n. 1 delle Dolomiti - Dolomiten-Höhenweg Nr. 1": "Alta Via 1 Dolomites",
    "Alta Via n. 2 delle Dolomiti - Dolomiten-Höhenweg Nr. 2": "Alta Via 2 Dolomites",
    "Alta Via n. 1 della Valle d'Aosta": "Alta Via 1 Aosta",
}
ways = (
    treks.select(trek=pl.col("name").replace(short), stages="stages")
    .explode("stages")
    .unnest("stages")
    .rename({"id": "stage_id", "name": "stage"})
    .explode("ways")
    .unnest("ways")
    .rename({"id": "way_id"})
)
print(ways.shape)
ways.select("trek", "stage", "way_id", "length", "points").head(4)

# %% [markdown]
# Now the tags. OpenStreetMap grades mountain paths on the SAC scale, from Swiss Alpine
# Club practice: T1 is a walk, T3 a demanding mountain path, T5 and T6 alpine terrain
# where you may need your hands and a head for heights. `struct.field` picks it out of
# the big tags struct, and a group-by sums the lengths per grade.

# %%
# id: s07_sac
grades = {"hiking": "T1", "mountain_hiking": "T2", "demanding_mountain_hiking": "T3",
          "alpine_hiking": "T4", "demanding_alpine_hiking": "T5", "difficult_alpine_hiking": "T6"}
sac = (
    ways.with_columns(sac=pl.col("tags").struct.field("sac_scale").replace_strict(grades, default="none"))
    .group_by("trek", "sac")
    .agg(km=pl.col("length").sum() / 1000)
    .pivot(on="sac", index="trek", values="km", sort_columns=True)
    .fill_null(0)
    .sort("trek")
)
sac

# %% [markdown]
# OpenStreetMap stores the grades as words (`mountain_hiking`), which we map back to
# the T1-T6 the signposts use; `none` means no grade was mapped (often roads and forest
# tracks).
# The SAC grades also tell the treks apart: the Dolomite Alte Vie and the Tour du Cervin
# have kilometres of T4 and harder, the Tour du Mont Blanc stays mostly on
# T1-T2 paths.
#
# ## 8. Points: lists, arrays, and a map projection
#
# Each point is `[x, y, elevation]`. The x and y are Web Mercator metres, the projection
# of every web map. Since every point has exactly three values, we can cast the inner
# list to a fixed-size **array**, and read it with the `arr` namespace.

# %%
# id: s08_points
R = 6378137.0  # Web Mercator sphere radius, metres
pts = (
    ways.select("trek", "stage", "way_id", "points")
    .with_row_index("way_seq")
    .explode("points")
    .with_columns(pl.col("points").cast(pl.Array(pl.Float64, 3)))
    .select(
        "trek", "stage", "way_seq",
        x=pl.col("points").arr.get(0),
        y=pl.col("points").arr.get(1),
        ele=pl.col("points").arr.get(2),
    )
    .with_columns(
        lon=pl.col("x") / R * 180 / math.pi,
        lat=(pl.col("y") / R).sinh().arctan() * 180 / math.pi,
    )
)
print(pts.height)
pts.head(4)

# %% [markdown]
# A distance in Web Mercator metres is stretched by 1/cos(latitude), about 1.43 at 46°N,
# so we shrink each step back. Steps are measured within a way, so gaps between
# disconnected ways don't count.

# %%
# id: s08_distance
pts = pts.with_columns(
    step=((pl.col("x").diff() ** 2 + pl.col("y").diff() ** 2).sqrt()
          * (pl.col("lat") * math.pi / 180).cos()).over("way_seq").fill_null(0)
).with_columns(km=pl.col("step").cum_sum().over("trek") / 1000)
pts.group_by("trek").agg(
    km=pl.col("step").sum() / 1000,
    top=pl.col("ele").max(),
    bottom=pl.col("ele").min(),
).sort("km")

# %%
# id: fig_treks
figs.treks_map(pts, peaks)

# %% [markdown]
# Two of the eight are far to the east, in the Dolomites, where the limestone towers top
# out at 3343 m (the Marmolada) and there are no four-thousanders at all.

# %%
# id: fig_dolomites
figs.dolomites_map(pts)

# %% [markdown]
# ## 9. How much climbing? It depends on how closely you look
#
# Guidebooks give the Tour du Mont Blanc about 170 km and **10,000 metres of ascent**.
# Our 166 km match the first number. For the second, you add up every rise along the
# way. But a terrain model has noise, and every little up-and-down gets counted, so the
# answer depends on how finely you sample. Average the height over bins of increasing
# length and watch the total ascent shrink.

# %%
# id: s09_ascent
def ascent(bin_km):
    return (
        pts.group_by("trek", (pl.col("km") / bin_km).floor().alias("bin"))
        .agg(pl.col("ele").mean())
        .sort("trek", "bin")
        .group_by("trek")
        .agg(pl.col("ele").diff().clip(lower_bound=0).sum().round().alias(f"{int(bin_km * 1000)} m"))
    )

table = ascent(0.05)
for b in [0.1, 0.2, 0.5, 1.0]:
    table = table.join(ascent(b), on="trek")
table.sort("trek")

# %% [markdown]
# Bins of 100 metres give the Tour du Mont Blanc 10,183 metres, right on the guidebook
# figure; with 1 km bins the passes are smoothed away and only 8,257 m remain. We'll use
# 100 metres from here on.

# %%
# id: fig_profile
passes = pl.DataFrame({
    "km": [8.0, 23.6, 48.0, 64.1, 73.3, 105.5, 152.3],
    "label": ["Brévent", "Col de Voza", "Croix du Bonhomme", "Col de la Seigne",
              "Mont Favre", "Grand Col Ferret", "Col de Balme"],
})
tmb = pts.filter(pl.col("trek") == "Tour du Mont Blanc").sort("km")
labels = passes.join_asof(tmb.select("km", "ele"), on="km", strategy="nearest")
figs.profile(pts, "Tour du Mont Blanc", labels)

# %% [markdown]
# ## 10. The guidebook's words, decoded
#
# The Aosta Valley's Alta Via 1 is split into 17 official stages, and each stage in
# OpenStreetMap carries its itinerary as a list of strings with the altitude written in:
# `Sassa (1430 mt.)`. `list.eval` runs an expression on every element of a list, so we
# can pull the numbers out of all of them at once and compare them with what the
# terrain model says at the start and end of each stage.

# %%
# id: s10_stages
av1 = (
    ways.filter(pl.col("trek") == "Alta Via 1 Aosta")
    .group_by("stage_id", maintain_order=True)
    .agg(pl.col("stage").first(), pl.col("itinerary").first())
    .with_columns(
        stop_m=pl.col("itinerary").list.eval(
            pl.element().str.extract(r"\((\d[\d.]*)\s*mt?\.?\)").str.replace_all(r"\.", "").cast(pl.Int64)
        ),
        stage_no=pl.col("stage").str.extract(r"Tappa (\d+)").cast(pl.Int64),
    )
    .sort("stage_no")
)
av1.select("stage_no", "itinerary", "stop_m").head(6)

# %% [markdown]
# Now the check. For each stage, take the terrain height at its first and last point,
# put them in a list too, and compare the two lists element by element.

# %%
# id: s10_check
ends = pts.group_by("stage", maintain_order=True).agg(
    dem_m=pl.concat_list(pl.col("ele").first(), pl.col("ele").last()).first()
)
check = av1.join(ends, on="stage").with_columns(
    diff_m=pl.max_horizontal(
        (pl.col("dem_m").list.get(i) - pl.col("stop_m").list.get(i)).abs() for i in (0, 1)
    ).round().cast(pl.Int64)
)
check.filter(pl.col("diff_m") > 150).select("stage_no", "itinerary", "stop_m", "dem_m", "diff_m")

# %% [markdown]
# Fourteen of the seventeen stages agree with the terrain within 150 metres, about as
# close as you can expect from a terrain model and a signpost. Two of the misfits share
# one typo: the village of Niel is written `Niel 1(550 mt.)`, a misplaced bracket that
# turns 1550 m into a 550-metre valley floor (the terrain says 1567). The third is a hole
# in the map: stage 15 should climb to the Rifugio Frassati at 2540 m, but its mapped path
# stops 500 metres lower, and stage 16 picks up from the hut.

# %% [markdown]
# ## 11. Walking time, with a Nim callback
#
# Swiss and German signposts give walking times, not distances, using a rule of thumb
# (DIN 33466): 4 km per hour on the flat, 300 metres of ascent per hour, 500 metres of
# descent per hour; take the larger of the horizontal and vertical times and add half
# the smaller.
#
# That rule fits in an expression, but it reads better as a plain function, and that is
# what callbacks are for: `map_elements` hands each value (here a struct with three
# fields) to your own function. In Nim, the function is a regular proc on a tuple, and
# runs at native speed.

# %%
# id: s11_time
def walking_hours(s):
    horizontal = s["km"] / 4
    vertical = s["up"] / 300 + s["down"] / 500
    return max(horizontal, vertical) + min(horizontal, vertical) / 2

legs = (
    pts.group_by("trek", (pl.col("km") / 0.1).floor().alias("bin"))
    .agg(pl.col("ele").mean(), pl.col("km").max())
    .sort("trek", "bin")
    .with_columns(d=pl.col("ele").diff().over("trek").fill_null(0))
    .group_by("trek")
    .agg(
        km=pl.col("km").max(),
        up=pl.col("d").clip(lower_bound=0).sum(),
        down=-pl.col("d").clip(upper_bound=0).sum(),
    )
    .with_columns(
        hours=pl.struct("km", "up", "down").map_elements(walking_hours, return_dtype=pl.Float64)
    )
    .with_columns(days_of_7h=(pl.col("hours") / 7).round(1))
    .sort("hours")
)
legs

# %% [markdown]
# The rule puts the Tour du Mont Blanc at 75 hours of walking, just under 11 days of
# seven hours, which is the classic 11-stage itinerary. The Aosta Valley's Alta Via 1
# is the longest of the eight, more than two weeks.
#
# The callback also rescues the first ascents from section 4. When a party is written
# as "Jakob and Melchior Anderegg", the two people share one surname, and no regular
# expression is going to know which words are first names. A small function can: if an
# entry is a single word and the next one has a surname, borrow it.

# %%
# id: s11_names
def lend_surnames(party):
    out = []
    for i, name in enumerate(party):
        if " " not in name and name[:1].isupper() and i + 1 < len(party) and " " in party[i + 1]:
            name = name + " " + party[i + 1].split(" ")[-1]
        out.append(name)
    return out

fixed = ascents.with_columns(
    party=pl.col("party").map_elements(lend_surnames, return_dtype=pl.List(pl.String))
)
fixed.explode("party").filter(pl.col("party").str.contains("Anderegg"))["party"].value_counts(sort=True)

# %% [markdown]
# The ranking doesn't move, but the Anderegg family is now complete:
#
# ## 12. Asking in SQL
#
# Not everyone thinks in method chains. Nanuq 0.5 can register frames in a SQL context
# and query them by name. Which range has the most four-thousanders, and how high and
# prominent are they?

# %%
# id: s12_sql
ctx = pl.SQLContext(peaks=peaks.drop("countries"), treks=legs)
ctx.execute("""
    SELECT range, CAST(COUNT(*) AS BIGINT) AS n, MAX(height) AS highest, ROUND(AVG(prom_m)) AS avg_prom
    FROM peaks
    GROUP BY range
    ORDER BY n DESC, highest DESC
""", eager=True)

# %% [markdown]
# ## Part 2: The world
#
# ## 13. Every mountain range on Earth
#
# Geographers at the University of Bern (the GMBA, Global Mountain Biodiversity
# Assessment) have drawn the outline of every named mountain range on Earth, and put
# them into a hierarchy: Alps, Western Alps, Pennine Alps, and so on. We use their
# selection of about 300 major ranges, saved as NDJSON with the outlines simplified
# (`src/gmba_prep.py`). The `Path` column is the hierarchy as one string,
# `Europe > Alps`, and `Countries` is another list in disguise.

# %%
# id: s13_ranges
ranges = pl.read_ndjson("data/gmba_ranges.ndjson").with_columns(
    path=pl.col("Path").str.split(" > "),
    countries=pl.col("Countries").str.split(", "),
)
ranges.select("MapName", "path", "Elev_High", "countries").sort("Elev_High", descending=True).head(6)

# %% [markdown]
# The heights are a fact check of their own. GMBA computes them from a terrain model
# with cells of a few hundred metres, which shaves off the sharpest tops: the Himalaya
# reach 8718 m in the inventory, Everest is 8849; the Alps 4713 m, Mont Blanc 4809.
#
# The first element of the path is the continent-sized system the range belongs to.
# Which ranges cross the most countries? (GMBA's Alps include the foothills, so they reach
# Hungary and Croatia, ten countries in all.)

# %%
# id: s13_countries
print(ranges.filter(pl.col("Feature") != "Ocean").select(
    "MapName", n=pl.col("countries").list.len(), top=pl.col("Elev_High")
).top_k(6, by="n"))
print(ranges.group_by(system=pl.col("path").list.first()).agg(
    n=pl.len(), highest=pl.col("Elev_High").max()
).top_k(8, by="highest"))

# %%
# id: fig_world
figs.world_map(ranges)

# %% [markdown]
# ## 14. Above 8000, according to Wikidata
#
# There are fourteen mountains higher than 8000 metres, all in the Himalaya and the
# Karakoram. Ask Wikidata, the free knowledge base behind Wikipedia, for every
# "mountain" with an elevation of at least 8000, and you get rather more.

# %%
# id: s14_wikidata
wd = pl.read_csv("data/wd_8000.csv").unique("m", keep="first")
print(wd.height)
wd.sort("elev", descending=True).select("mLabel", "elev", "coord", "countries").head(6)

# %% [markdown]
# Olympus Mons is on Mars (the coordinates start with the Wikidata id of the planet),
# and the long tail is mostly American summits whose height was entered in feet. Keep
# the Earth, keep metres (nothing on Earth is higher than Everest's 8849), split the
# climbers into a list, and look at what is left.

# %%
# id: s14_clean
high = (
    wd.filter(
        ~pl.col("coord").str.starts_with("<"),
        pl.col("elev") <= 8849,
        pl.col("countries").str.contains("Nepal|China|Pakistan|India"),
    )
    .select(
        peak="mLabel",
        height="elev",
        prom_m="prom",
        year=pl.col("date").str.slice(0, 4).cast(pl.Int32),
        party=pl.col("climbers").str.split("|"),
        countries=pl.col("countries").str.split("|"),
        where=pl.col("coord").str.extract_groups(r"Point\((?<lon>[-\d.]+) (?<lat>[-\d.]+)\)"),
    )
    .unnest("where")
    .with_columns(pl.col("lon", "lat").cast(pl.Float64))
    .sort("height", descending=True)
)
high.drop("lon", "lat")

# %% [markdown]
# Fifteen, not fourteen: Lhotse Shar rises only 86 metres above its col with Lhotse, the
# kind of bump the UIAA had to rule on in the Alps. Keep the peaks with at least 300 m of
# prominence and the classic fourteen are back. Then explode the parties: does anyone
# appear twice?

# %%
# id: s14_buhl
print(high.filter(pl.col("prom_m") >= 300).height)
high.explode("party").drop_nulls("party").group_by("party").agg(
    pl.col("peak"), n=pl.len()
).filter(pl.col("n") > 1)

# %% [markdown]
# Hermann Buhl, the Austrian who reached the top of Nanga Parbat alone in 1953 and was
# in the four-man team on Broad Peak in 1957, is the only person with two first ascents
# of 8000ers in our data. Here are the fifteen, with the coordinates we pulled out of
# Wikidata's `Point(lon lat)` strings:

# %%
# id: fig_himalaya
figs.himalaya_map(high)

# %% [markdown]
#
# ## 15. Two golden ages
#
# The fourteen were first climbed between Annapurna in 1950 and Shishapangma in 1964,
# a golden age of Himalayan climbing that looks a lot like the Alpine one a century
# earlier. Stack the two tables (`vstack` needs the same columns) and compare.

# %%
# id: s15_golden
alps = fixed.select("year", region=pl.lit("Alps 4000"))
himalaya = high.filter(pl.col("prom_m") >= 300).select("year", region=pl.lit("8000ers"))
both = alps.vstack(himalaya).drop_nulls()
both.group_by("region").agg(
    n=pl.len(),
    first=pl.col("year").min(),
    median=pl.col("year").median(),
    last=pl.col("year").max(),
    years_for_middle_half=pl.col("year").quantile(0.75) - pl.col("year").quantile(0.25),
).sort("region")

# %% [markdown]
# The middle half of the Alpine first ascents took 22 years; for the Himalayan giants it
# took 3.
#
# ## 16. Saving it, as JSON
#
# Nested data goes back to JSON as easily as it came in: one line per trek, with the
# stage list intact.

# %%
# id: s16_write
summary = legs.with_columns(pl.col("km", "up", "down", "hours").round(1)).join(
    ways.group_by("trek").agg(stages=pl.col("stage").unique(maintain_order=True)),
    on="trek", how="left", maintain_order="left",
)
path = os.path.join(tempfile.gettempdir(), "treks_summary.ndjson")
summary.write_ndjson(path)
print(open(path).readline().rstrip("\n")[:200])
