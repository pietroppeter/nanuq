# %% [markdown]
# # Counting El Niños
#
# *Nanuq 0.4 explainer, Python draft (py-polars 2.1). Every cell below will become a Nim
# block in the dev log post, written against the 0.4 API; the outputs here are what the
# Nim version must print.*
#
# Every few years a patch of the Pacific Ocean, out in the middle of nowhere, warms up by
# a degree or two. That sounds like nothing. Yet it floods deserts in Peru, dries out
# rainforests in Indonesia, shifts storm tracks over North America, and nudges the
# temperature of the whole planet. The warming is called **El Niño**, and right now, in
# the autumn of 2026, one of the strongest on record is under way.
#
# This post counts El Niños the way the scientists do, starting from a single column of
# monthly sea temperatures, and follows them out into the rest of the world's weather.
# Nothing is assumed: if you have never heard of El Niño, this is the place to start.
# Along the way it shows off what is new in Nanuq 0.4: rolling windows and exponential
# smoothing, cumulative functions, shift and diff, top-k and binning, horizontal
# functions, pivot and unpivot, dynamic group-by, as-of joins and a real `Series`.
#
# Data, all public: NOAA's Climate Prediction Center (CPC) for the Niño indices and the
# Southern Oscillation Index, NASA GISS (GISTEMP v4) for global temperature, and NOAA's
# GHCN-Daily for the rain gauge at Piura airport, Peru. Downloaded on 1 November 2026.

# %%
# id: setup
import datetime as dt
import polars as pl

pl.Config(tbl_rows=12, tbl_cols=10, tbl_width_chars=120, float_precision=2);

import sys; sys.path.insert(0, "src")
import figs  # Plotly charts and maps; the Nim post redoes them with nim-plotly

# %% [markdown]
# ## 1. A box in the ocean
#
# Along the equator, the trade winds blow from east to west across the Pacific. They push
# the sun-warmed surface water towards Indonesia and Australia, where it piles up, and let
# cold water well up from the deep along the coast of South America. So the Pacific is
# normally warm in the west and cool in the east.
#
# Every two to seven years the trade winds weaken, the warm water sloshes back east, and
# the central and eastern Pacific heat up. Fishermen in Peru noticed this centuries ago,
# because it came around Christmas and emptied their nets. They called it *El Niño de
# Navidad*, the Christmas child.

# %%
# id: fig_walker
figs.walker_schematic()

# %% [markdown]
# Here is the same ocean seen from above: the mean sea surface temperature of
# 1991-2020. The warm pool sits in the west, the cold tongue stretches out from South
# America along the equator.

# %%
# id: fig_normal
figs.pacific_normal()

# %% [markdown]
# To keep watch, scientists average the sea surface temperature over a box on the equator
# called **Niño 3.4** (5°N to 5°S, 120°W to 170°W): about 1,100 by 5,500 km, six million
# square kilometres of open ocean with no land in it (the black box on the map). CPC
# publishes one number per month for that box, back to 1950. Here it is, read into a frame, and its temperature column taken out as a
# `Series`, Nanuq 0.4's new one-column type.

# %%
# id: s01_box
nino = pl.read_csv("data/nino34.csv").select("year", "month", "sst")
print(nino.tail(4))
sst = nino["sst"]
print(f"{sst.len()} months, from {sst.min():.2f} to {sst.max():.2f} °C")
print(nino[sst.arg_max()])

# %% [markdown]
# The warmest month in 76 years of records was September 2026, the latest month in the
# file. But a warm month is not yet an El Niño: the ocean has seasons too. The mean for
# each calendar month, with `topK` and `bottomK`, shows the box is warmest in spring and
# coolest in winter, more than a degree apart.

# %%
# id: s01_seasons
climate = nino.group_by("month").agg(pl.col("sst").mean())
print(pl.concat([climate.top_k(2, by="sst"), climate.bottom_k(2, by="sst")]))

# %% [markdown]
# ## 2. What is normal?
#
# Climate scientists rarely look at a temperature on its own. They look at the
# **anomaly**: how far a month is above or below normal for that time of year. "Normal"
# is the average of the same calendar month over a 30-year **base period**, today
# 1991-2020.
#
# In Nanuq that is one window expression: the mean of `sst` over the base years,
# computed separately for each month with `over`.

# %%
# id: s02_anomaly
base = pl.col("year").is_between(1991, 2020)
nino = nino.with_columns(
    normal=pl.col("sst").filter(base).mean().over("month"),
).with_columns(anomaly=pl.col("sst") - pl.col("normal"))
print(nino.filter(pl.col("month") == 9, pl.col("year").is_in([1982, 1997, 2015, 2023, 2026])))

# %% [markdown]
# September 2026 was 2.5 °C above a normal September: the ocean is running a fever.
#
# The same idea works for every point of the ocean. Here are three Septembers, each
# compared with a normal September: the two biggest El Niños of the satellite era, and
# this one.

# %%
# id: fig_three_septembers
figs.anomaly_maps(["1997-09", "2015-09", "2026-09"],
                  ["September 1997", "September 2015", "September 2026"])

# %% [markdown]
# CPC does one thing differently. It does not use a single base period for all 76 years
# but a sliding one, so that each year is compared with the 30 years around it. The file
# also carries CPC's own anomaly, and we will see in scene 7 why the difference matters.

# %% [markdown]
# ## 3. Three months make a season
#
# A single warm month can be a fluke of the weather. So the official **Oceanic Niño
# Index (ONI)** is a three-month running mean of the anomaly: the value for "DJF" is the
# mean of December, January and February, and so on through the twelve overlapping
# seasons of the year.
#
# CPC publishes the ONI as a wide table, one row per year and one column per season,
# rounded to one decimal. That shape is good for reading, bad for computing. `unpivot`
# turns it into one row per season, and `replaceStrict` maps each season to its middle
# month.

# %%
# id: s03_table
seasons = ["DJF", "JFM", "FMA", "MAM", "AMJ", "MJJ", "JJA", "JAS", "ASO", "SON", "OND", "NDJ"]
oni_table = pl.read_csv("data/oni_table.csv")
print(oni_table.tail(3))
oni = (oni_table.unpivot(index="year", variable_name="season", value_name="oni")
       .drop_nulls("oni")
       .with_columns(month=pl.col("season").replace_strict(
           {s: m for m, s in enumerate(seasons, start=1)}, return_dtype=pl.Int64))
       .sort("year", "month"))
print(oni.tail(3))

# %% [markdown]
# Now we rebuild the index ourselves from CPC's monthly anomalies, with a centered
# `rollingMean` over three rows, and compare.

# %%
# id: s03_rebuild
cpc = pl.read_csv("data/nino34.csv").select(
    "year", "month", mine=pl.col("cpc_anomaly").rolling_mean(3, center=True))
check = oni.join(cpc, on=["year", "month"]).with_columns(diff=(pl.col("mine") - pl.col("oni")).abs())
print(check.select(seasons=pl.len(), max_diff=pl.col("diff").max(),
                   off_by_rounding=(pl.col("mine").round(1) != pl.col("oni")).sum()))

# %% [markdown]
# All 920 seasons agree to within 0.05 °C, which is the rounding of the table. Only 14
# land on the other side of a rounding tie (CPC averages the unrounded values). We have
# rebuilt NOAA's El Niño index in one line.

# %% [markdown]
# ## 4. Counting El Niños
#
# The rule for an El Niño **event** is simple: the ONI must be at **+0.5 °C or more for
# at least five overlapping seasons in a row**. Its cold mirror image, at -0.5 °C or less,
# is called **La Niña** (the girl). Anything in between is "neutral". Together they make
# the **El Niño-Southern Oscillation**, ENSO for short.
#
# Finding runs is a job for `rleId`: it gives every run of equal values its own number.
# Label each season with its phase, number the runs, and keep the runs at least five
# seasons long.

# %%
# id: s04_events
phase = (pl.when(pl.col("oni") >= 0.5).then(pl.lit("El Niño"))
         .when(pl.col("oni") <= -0.5).then(pl.lit("La Niña"))
         .otherwise(pl.lit("neutral")))
events = (oni.with_columns(phase=phase)
          .with_columns(run=pl.col("phase").rle_id())
          .group_by("run", maintain_order=True)
          .agg(pl.col("phase").first(),
               start=pl.format("{} {}", pl.col("season").first(), pl.col("year").first()),
               end=pl.format("{} {}", pl.col("season").last(), pl.col("year").last()),
               seasons=pl.len(),
               peak=pl.col("oni").max(), trough=pl.col("oni").min(),
               start_date=pl.date(pl.col("year").first(), pl.col("month").first(), 15))
          .filter(pl.col("phase") != "neutral", pl.col("seasons") >= 5)
          .drop("run"))
print(events["phase"].value_counts(sort=True))
print(events.tail(5).drop("start_date"))

# %% [markdown]
# 25 El Niños and 21 La Niñas since 1950. CPC colours its table red and blue with the
# same rule, and our runs match its colouring season by season, all 920 of them. One
# detail matters: the rule is applied to the rounded table. On CPC's two-decimal file,
# where a +0.46 does not reach +0.5, the same code finds only 22 El Niños.
#
# Look at the last row: the current El Niño began in MAM (March to May) 2026 and is
# still going, so it has no end yet. It already counts as an event: JAS is its fifth
# season.
#
# The whole record at a glance, red when the index is at +0.5 or more, blue at -0.5 or
# less.

# %%
# id: fig_oni_bars
figs.oni_bars(oni)

# %% [markdown]
# ## 5. How strong?
#
# Forecasters grade events by their peak: weak from +0.5, moderate from +1.0, strong
# from +1.5, very strong from +2.0. `cut` does the binning; `leftClosed` makes each band
# include its lower edge. Then `topK` picks the five biggest El Niños.

# %%
# id: s05_strength
ninos = (events.filter(pl.col("phase") == "El Niño")
         .with_columns(strength=pl.col("peak").cut(
             [1.0, 1.5, 2.0], labels=["weak", "moderate", "strong", "very strong"],
             left_closed=True)))
print(ninos["strength"].value_counts().sort("strength"))
print(ninos.top_k(5, by="peak").select("start", "end", "seasons", "peak", "strength"))

# %% [markdown]
# The famous ones are all there: 1982-83, 1997-98 and 2015-16 (which by this index
# started in late 2014), the three "super El Niños" of the satellite era, and 2023-24,
# which just makes the very strong band. The current event is already in third place at
# 2.2 and, according to CPC's October discussion, still strengthening.
#
# And here is what "very strong" looks like next to its opposite: December 1997, at the
# peak of the 1997-98 El Niño, and December 1988, at the peak of a strong La Niña, when
# the cold tongue reached far into the central Pacific.

# %%
# id: fig_nino_nina
figs.anomaly_maps(["1997-12", "1988-12"], ["El Niño, December 1997", "La Niña, December 1988"])

# %% [markdown]
# ## 6. 2026, the fast one
#
# How quickly did this one arrive? `diff` gives the change from one season to the next,
# and `shift(4)` lets us compare each season with four seasons earlier, about the time it
# takes an El Niño to grow.

# %%
# id: s06_rise
rise = oni.with_columns(
    step=pl.col("oni").diff(),
    rise4=pl.col("oni") - pl.col("oni").shift(4),
)
print(rise.filter(pl.col("year") == 2026).select("season", "oni", "step", "rise4"))
print(rise.top_k(5, by="rise4").select("year", "season", "oni", "rise4"))

# %% [markdown]
# From MAM to JAS 2026 the index climbed 1.7 °C, the fastest four-season rise since
# 1950, ahead of 1997. To line events up from their first season, `cumCount` over each
# run counts the seasons since onset, and `pivot` puts the big events side by side.

# %%
# id: s06_side_by_side
big = [1982, 1997, 2014, 2023, 2026]
runs = (oni.with_columns(phase=phase)
        .with_columns(run=pl.col("phase").rle_id())
        .with_columns(onset=pl.col("year").first().over("run"),
                      season_no=pl.col("oni").cum_count().over("run"))
        .filter(pl.col("phase") == "El Niño", pl.col("onset").is_in(big),
                pl.col("season_no") <= 8))
side = runs.pivot(on="onset", index="season_no", values="oni")
print(side)

# %% [markdown]
# Five seasons in, 2026 is ahead of every other event, 1997 included. (The 2014 column
# is the 2015-16 event, which began in late 2014 and then idled for months around +0.7
# before taking off.)

# %%
# id: fig_growth
figs.growth(side)

# %% [markdown]
# ## 7. A moving ruler
#
# Here is a problem. The whole tropical ocean is getting warmer. If "normal" stays fixed,
# a warming ocean looks more and more like El Niño, even when nothing special is going
# on. Our fixed 1991-2020 anomaly from scene 2 shows it: `groupByDynamic` with a
# ten-year window gives the mean anomaly of each decade.

# %%
# id: s07_drift
monthly = (pl.read_csv("data/nino34.csv")
           .with_columns(date=pl.date("year", "month", 1))
           .join(nino.select("year", "month", "anomaly"), on=["year", "month"]))
print(monthly.filter(pl.col("year") >= 1950).group_by_dynamic("date", every="10y").agg(
    fixed_base=pl.col("anomaly").mean(), sliding_base=pl.col("cpc_anomaly").mean()))

# %% [markdown]
# Against a fixed base, every decade before 1990 averages 0.2 to 0.5 °C below zero:
# the 1950s to 1980s look like a forty-year La Niña. CPC's sliding base keeps every decade
# near zero, but it is always computed from past years, so it lags behind a fast
# warming. So since February 2026 NOAA uses a new official index, the **Relative ONI
# (RONI)**: the Niño 3.4 anomaly minus the average anomaly of the whole tropics (20°N to
# 20°S), rescaled to the same spread. El Niño is now measured against the rest of the
# tropical ocean, not against the past.
#
# Same rules, new ruler: count the events again with RONI and match them to the ONI
# events with `joinAsof`, which pairs each ONI event with the RONI event that started
# nearest in time, if within six months.

# %%
# id: s07_roni
roni = (pl.read_csv("data/roni_table.csv")
        .unpivot(index="year", variable_name="season", value_name="oni")
        .drop_nulls("oni")
        .with_columns(month=pl.col("season").replace_strict(
            {s: m for m, s in enumerate(seasons, start=1)}, return_dtype=pl.Int64))
        .sort("year", "month"))
roni_events = (roni.with_columns(phase=phase)
               .with_columns(run=pl.col("phase").rle_id())
               .group_by("run", maintain_order=True)
               .agg(pl.col("phase").first(), seasons=pl.len(),
                    roni_start=pl.format("{} {}", pl.col("season").first(), pl.col("year").first()),
                    roni_peak=pl.col("oni").max(),
                    start_date=pl.date(pl.col("year").first(), pl.col("month").first(), 15))
               .filter(pl.col("phase") == "El Niño", pl.col("seasons") >= 5)
               .select("start_date", "roni_start", "roni_peak"))
print(f"ONI: {ninos.height} El Niños, RONI: {roni_events.height}")
paired = ninos.sort("start_date").join_asof(
    roni_events.sort("start_date"), on="start_date", strategy="nearest",
    tolerance=dt.timedelta(days=183), coalesce=False)
print(paired.filter(pl.col("start_date").dt.year() >= 2000)
      .select("start", "peak", "roni_start", "roni_peak"))
print(roni_events.top_k(3, by="roni_peak")
      .sort("roni_peak", "start_date", descending=[True, False]))

# %% [markdown]
# Both rulers count 25 El Niños since 1950, but not quite the same ones, and not equally
# strong. Since 2000 the two lists mostly agree, with three exceptions:
#
# - 2023-24 shrinks from 2.0 to 1.4. It peaked while the whole tropical ocean was
#   unusually hot, so relative to its surroundings it was a moderate event.
# - The weak 2019-20 warm spell is not an El Niño by RONI.
# - Neither is the current one, yet. By RONI it reached +0.5 only in AMJ, so JAS was its
#   fourth season. NOAA has nevertheless issued an El Niño Advisory: the five-season
#   rule is for the history books, while forecasters declare an event as soon as ocean
#   and atmosphere agree and are expected to stay that way.
#
# The RONI record holder is 1982-83 at +2.4. That is why CPC's October discussion speaks
# of a "historic event" if the 3-month RONI reaches +2.5 or more, which it gives a 54%
# chance for September-November and 83% for October-December.
#
# Side by side since 1995, the two rulers mostly agree on the ups and downs. They part
# ways where the whole tropics were warm: 2023 and now.

# %%
# id: fig_rulers
figs.two_rulers(oni, roni)

# %% [markdown]
# ## 8. The other half: air pressure
#
# El Niño is not only about water. In the 1920s the British scientist Gilbert Walker,
# looking for a way to forecast India's monsoon, found a seesaw in air pressure across
# the Pacific: when pressure is high in the east it is low in the west, and vice versa.
# He called it the **Southern Oscillation**. Today it is measured as the **Southern
# Oscillation Index (SOI)**: the pressure at Tahiti minus the pressure at Darwin,
# Australia, standardized. When the trade winds weaken, the SOI drops.
#
# In 1969 the Norwegian meteorologist Jacob Bjerknes showed that Walker's seesaw and the
# warm Pacific water were one coupled system: weaker trade winds let the ocean warm, and
# a warmer east Pacific weakens the trade winds further. `corr` shows how tightly the
# two move together, here on three-month means of both.

# %%
# id: s08_soi
soi = pl.read_csv("data/soi.csv").with_columns(soi3=pl.col("soi").rolling_mean(3, center=True))
both = soi.join(cpc, on=["year", "month"]).drop_nulls()
print(both.select(months=pl.len(), r=pl.corr("soi3", "mine")))
print(both.filter(pl.col("year") == 2026).tail(4))

# %% [markdown]
# A correlation of -0.84 over 75 years: when the sea warms, the pressure seesaw tips. In
# 2026 the SOI swung from positive (La Niña) in the winter to negative in April, and
# has stayed there as the ocean warmed.

# %%
# id: fig_soi
figs.soi_vs_oni(both)

# %% [markdown]
# ## 9. Four boxes and a coastal surprise
#
# Niño 3.4 is not the only box. CPC also tracks Niño 1+2, right off the coast of Peru and
# Ecuador, Niño 3 in the east and Niño 4 in the west. The horizontal functions compare
# columns within each row: `maxHorizontal` finds the hottest box, `meanHorizontal` the
# average of the four.

# %%
# id: s09_boxes
anoms = ["nino12_anom", "nino3_anom", "nino34_anom", "nino4_anom"]
boxes = pl.read_csv("data/nino_boxes.csv").select("year", "month", *anoms).with_columns(
    hottest=pl.max_horizontal(anoms), mean=pl.mean_horizontal(anoms),
)
print(boxes.tail(3))
coastal = boxes.filter(pl.col("nino12_anom") >= 1.0, pl.col("nino34_anom").abs() < 0.5)
print(coastal.group_by("year").agg(months=pl.len(), coast_max=pl.col("nino12_anom").max()).sort("year"))

# %% [markdown]
# In September 2026 the coastal box is 4.7 °C above normal, far ahead of the other
# three. The second table hunts for the opposite: months when the coast was at least a
# degree too warm while Niño 3.4 stayed neutral. Some are the tail of a big event (the
# coast stayed hot in mid-1983 after the centre cooled). Others, like early 2017 and
# early 2023, are "coastal El Niños" (*El Niño costero*): no event at all by NOAA's
# index, and floods in Peru all the same.
#
# Three of the boxes since 2014 show both stories: in 2017 only the coast warmed; in 2023
# and 2026 the coast warmed first and the centre followed.

# %%
# id: fig_box_lines
figs.box_lines(boxes)

# %% [markdown]
# On the map, March 2017 next to September 2026, with all four boxes drawn.

# %%
# id: fig_coastal_maps
figs.anomaly_maps(["2017-03", "2026-09"], ["Coastal El Niño, March 2017", "September 2026"],
                  boxes=("Niño 4", "Niño 3.4", "Niño 3", "Niño 1+2"))

# %% [markdown]
# ## 10. Rain in the desert
#
# What does that mean on the ground? Piura, in northern Peru, sits in a coastal desert:
# a typical year brings a few tens of millimetres of rain. Its airport's rain gauge has
# daily readings in NOAA's GHCN-Daily archive. `groupByDynamic` with a one-year window
# sums them per year, and counts the days that were actually reported, because a gauge
# that stopped reporting is not a dry year.

# %%
# id: s10_piura
rain = pl.read_csv("data/piura_rain.csv", try_parse_dates=True).sort("date")
years = rain.group_by_dynamic("date", every="1y").agg(
    rain_mm=pl.col("rain_mm").sum(), days=pl.len())
print(years.select(pl.col("rain_mm").filter(pl.col("days") >= 300).median().alias("median, complete years")))
print(years.top_k(4, by="rain_mm"))

# %%
# id: fig_piura
figs.piura(years)

# %% [markdown]
# In 1983 Piura got about 2,400 mm of rain, in 1998 about 1,700 mm, with two months of
# readings missing: more than fifty times a normal year, in a city that has no rain
# gutters. (A peer-reviewed tally for the city, Takahashi 2004, gives 2,147 mm for
# 1982-83 and 1,802 mm for 1997-98: the same picture.) Third is 2017, the coastal El
# Niño, with only 79 days on record. A 30-day `rollingSumBy` on the date column finds
# the wettest month.

# %%
# id: s10_wettest
print(rain.with_columns(mm_30d=pl.col("rain_mm").rolling_sum_by("date", window_size="30d"))
      .top_k(1, by="mm_30d"))

# %% [markdown]
# A thousand millimetres in the thirty days to 1 May 1983, 305 of them on that last day
# alone, as the station record has it: more than London gets in a whole typical year, in
# one month, in a desert.

# %% [markdown]
# ## 11. The world's temperature
#
# El Niño does not only move heat around, it lets the ocean give heat back to the air,
# and the whole planet warms for a while. To see it we need the global temperature.
# NASA's GISTEMP gives the global mean surface temperature anomaly for each month since
# 1880, against a 1951-1980 base (NASA's choice; the base only shifts the numbers, not
# their differences). The file is another wide table, with one column per month and
# `***` for months not yet measured.

# %%
# id: s11_world
months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
gistemp = pl.read_csv("data/gistemp.csv", skip_rows=1, null_values="***")
world = (gistemp.select("Year", *months)
         .unpivot(index="Year", variable_name="mon", value_name="temp")
         .with_columns(date=pl.date(pl.col("Year"), pl.col("mon").replace_strict(
             {m: i for i, m in enumerate(months, start=1)}, return_dtype=pl.Int64), 1))
         .drop_nulls("temp").sort("date").select("date", "temp"))
yearly = gistemp.select(year="Year", temp="J-D").drop_nulls()
print(yearly.top_k(5, by="temp"))

# %% [markdown]
# Each new record year breaks the previous best. `cumMax` keeps the running best, so a
# record is a year equal to it (and higher than the year before the record).

# %%
# id: s11_records
records = yearly.filter(
    pl.col("temp") == pl.col("temp").cum_max(),
    pl.col("temp") > pl.col("temp").cum_max().shift(1),
)
print(records.filter(pl.col("year") >= 1980)["year"].to_list())

# %% [markdown]
# Month-to-month the global temperature is noisy. An exponentially weighted mean,
# `ewmMean`, smooths it by giving recent months more weight; with `span = 12` it acts
# like a one-year average that reacts faster than a plain 12-month rolling mean.

# %%
# id: s11_smooth
smooth = world.with_columns(
    rolling12=pl.col("temp").rolling_mean(12),
    ewm12=pl.col("temp").ewm_mean(span=12),
)
print(smooth.tail(6))

# %%
# id: fig_world
figs.world(yearly, smooth, records)

# %% [markdown]
# ## 12. El Niño's echo
#
# Does the planet warm *after* the Pacific does? Take the global temperature minus its
# own ten-year centered mean (to remove the long warming trend), and correlate it with
# the Niño 3.4 index shifted by 0 to 6 months.

# %%
# id: s12_lag
echo = (world.with_columns(year=pl.col("date").dt.year().cast(pl.Int64),
                           month=pl.col("date").dt.month().cast(pl.Int64))
        .join(cpc, on=["year", "month"])
        .with_columns(wiggle=pl.col("temp") - pl.col("temp").rolling_mean(121, center=True, min_samples=61)))
print(echo.select([pl.corr("wiggle", pl.col("mine").shift(k)).alias(f"{k} mo") for k in range(7)]))

# %% [markdown]
# The match is best when the global temperature lags the Pacific by two to three months.
# So a record year should follow an El Niño. `joinAsof` with the default backward
# strategy pairs every record year since 1980 with the last El Niño that started before
# its middle (1 July), if one started in the two years before.

# %%
# id: s12_records
recs = records.filter(pl.col("year") >= 1980).with_columns(date=pl.date("year", 7, 1))
with pl.Config(tbl_rows=20):
    print(recs.join_asof(ninos.select("start_date", "start", "peak", "strength").sort("start_date"),
                         left_on="date", right_on="start_date",
                         tolerance=dt.timedelta(days=730)).drop("date", "start_date"))

# %% [markdown]
# Twelve of the fourteen record years since 1980 came within two years of the start of
# an El Niño (1981 is a stretch: the weak 1979-80 event was already over). The other
# two, 1990 and 2014, came just before one began. Each of the last three very
# strong El Niños gave two record years in a row: 1997-98, 2015-16 and
# 2023-24. (The very strong 1982-83 event set no record: the eruption of El Chichón in
# Mexico in 1982 filled the stratosphere with sun-blocking haze and cooled the planet.)

# %% [markdown]
# ## 13. Hottest year on record?
#
# Which brings us to now. A pivot of the last four years, one column per year, puts each
# month next to the same month of the years before.

# %%
# id: s13_pivot
recent = (world.filter(pl.col("date").dt.year() >= 2023)
          .with_columns(year=pl.col("date").dt.year().cast(pl.String), mon=pl.col("date").dt.month())
          .pivot(on="year", index="mon", values="temp"))
print(recent.with_columns(hottest=pl.max_horizontal(pl.exclude("mon"))))

# %%
# id: fig_recent
figs.recent(recent)

# %% [markdown]
# August 2026 was the warmest August on record and September the second warmest, just
# behind 2023, also an El Niño year. Yet January to September 2026 still averages a
# little below 2024, because the year started in La Niña.

# %%
# id: s13_ytd
print(world.filter(pl.col("date").dt.month() <= 9)
      .group_by(year=pl.col("date").dt.year()).agg(pl.col("temp").mean(), months=pl.len())
      .top_k(3, by="temp"))

# %% [markdown]
# If the past is a guide, with a two-to-three-month echo and a peak expected around the
# turn of the year, the full heat of this El Niño reaches the global average in the first
# half of 2027. Whether 2026 itself beats 2024 depends on the last three months. We will
# count again in January.
#
# *Sources: NOAA CPC (ONI, RONI, Niño indices, SOI, ENSO Diagnostic Discussion of 8
# October 2026, RONI announcement); NASA GISS, GISTEMP v4; NOAA NCEI, GHCN-Daily station
# PEM00084401 (Piura); NOAA Ocean Service, "What are El Niño and La Niña?"; K. Takahashi
# (2004), Annales Geophysicae 22, 3917.*
