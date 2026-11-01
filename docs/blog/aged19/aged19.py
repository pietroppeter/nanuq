# %% [markdown]
# # Aged 19
#
# *The Python Polars version (py-polars 2.1) of the Nanuq 0.3 explainer
# (docs/blog/aged_19.nim). It was written first, to design the 0.3 API; each code cell
# matches one Nim block, and expected.py saves its outputs, which the Nim post must print.*
#
# Paul Seixas started the 2026 season as a 19-year-old in his second pro year. By
# October he had won the Tour of the Basque Country, the Flèche Wallonne and Il
# Lombardia, and finished fourth in the Tour de France. This post walks through his
# season, and through 130 years of the records he chased, with Nanuq 0.3's new tools:
# dates and durations, time zones, string expressions, Parquet and categoricals.
#
# Data: Wikipedia (CC BY-SA) for winner lists, stage winners, the Tour start lists of all
# 113 editions, birth dates, race dates, the 2026 calendar and the Giro standings; facts
# and quotes from [inrng](https://inrng.com).

# %%
# id: setup
import io
import datetime as dt
import polars as pl

pl.Config(tbl_rows=12, tbl_cols=10, tbl_width_chars=120, fmt_str_lengths=60);

# %% [markdown]
# ## 1. The season in one table
#
# The 2026 World Tour calendar fits in a CSV small enough to paste into a post. Nanuq
# 0.3 reads CSV from a string through a stream, and `tryParseDates` turns the ISO dates
# into real `Date` columns. `glimpse` shows every column on one line.

# %%
# id: s01_glimpse
season_csv = open("data/world_tour_2026.csv").read()
season = pl.read_csv(io.StringIO(season_csv), try_parse_dates=True)
print(season.glimpse(return_type="string"))

# %% [markdown]
# `glimpse` shows the types but hides the shape of the season. Printing all 36 rows
# needs more than the 12-row default, so the table is printed inside a config block that
# lifts the limit for one print only. The `days` column shows what one row can hide: a
# stage race is a single row, yet a week or three of racing, with a winner every day.

# %%
# id: s01_calendar
with pl.Config(tbl_rows=40):
    print(season.select("race", "start", "winner",
                        days=(pl.col("end") - pl.col("start")).dt.total_days() + 1))

# %% [markdown]
# ## 2. Who won what
#
# In cycling a win is a win, and there are three kinds. A one-day race (Sanremo,
# Flanders, Lombardia) has one winner. A stage race has a winner every day, and an
# overall winner at the end: the leader of the General Classification (GC), the rider
# with the lowest total time, who often wins no stage at all. So a rider's season is
# counted in all three: one-day wins, stage wins and GC wins. Team time trials are won by a team, and one Vuelta stage was
# cancelled by a hailstorm, so those stages have no individual winner.
#
# The stage winners come from each stage race's Wikipedia table. `concat` stacks the
# three kinds into one table of victories, with the kind as a small `Enum` column.

# %%
# id: s02_wins
Kind = pl.Enum(["one-day", "GC", "stage"])
stages = pl.read_csv("data/stages_2026.csv", try_parse_dates=True,
                     schema_overrides={"stage": pl.String})
victories = pl.concat([
    season.select("winner", race=pl.col("race").str.replace_all("–", "-"),
                  kind=pl.when(pl.col("start") == pl.col("end"))
                         .then(pl.lit("one-day")).otherwise(pl.lit("GC"))),
    stages.filter(pl.col("winner").is_not_null())
          .select("winner", race=pl.col("race").str.replace_all("–", "-") + " stage "
                  + pl.col("stage"), kind=pl.lit("stage")),
]).with_columns(pl.col("kind").cast(Kind))
with pl.Config(fmt_str_lengths=40):
  print(victories.group_by("winner")
      .agg(pl.len().alias("wins"),
           *[(pl.col("kind") == k).sum().alias(k) for k in Kind.categories],
           pl.col("race").filter(pl.col("kind") != "stage").str.join(", ").alias("races"))
      .filter(pl.col("wins") >= 6)
      .sort("wins", "GC", "winner", descending=[True, True, False]))

# %% [markdown]
# Pogačar won 22 times: four one-day races, three GCs (Romandie, Suisse,
# the Tour) and 15 stages. A Tour stage and a stage of the Renewi Tour count the same
# here, which is why sites like ProCyclingStats also weigh wins with points. Two other
# profiles stand out. Jonathan Milan won nine stages and nothing else, a sprinter's
# season. Seixas has an all-rounder's mix in his second pro year: two one-day races (Flèche Wallonne and
# Lombardia), the Basque Country GC and three of its six stages, the same six wins
# as Van der Poel and Evenepoel.

# %% [markdown]
#
# ## 3. Every Monument winner since 1892
#
# Five one-day races are called the Monuments. Their winners, 580 of them, with race
# dates and birth dates, are a good fit for Parquet: typed, compressed, read back
# lazily. Writing and scanning are new in 0.3.

# %%
# id: s03_parquet
monuments = pl.read_csv("data/monuments.csv", try_parse_dates=True).join(
    pl.read_csv("data/riders.csv", try_parse_dates=True), on="wiki", how="left"
)
monuments.write_parquet("monuments.parquet", compression="zstd")
lazy = pl.scan_parquet("monuments.parquet")
print(lazy.select(pl.len().alias("rows"), pl.col("year").min().alias("first"), pl.col("year").max().alias("last"),
                  pl.col("date").null_count().alias("no_date"),
                  pl.col("born").null_count().alias("no_birth_date")).collect())

# %% [markdown]
# Races are a fixed set, so they become a categorical. An `Enum` keeps the season's
# order, Sanremo in March to Lombardia in October, which sorting will respect. In Nim
# this is a plain `enum Monument`.

# %%
# id: s03_enum
Monument = pl.Enum(["Milano-Sanremo", "Ronde van Vlaanderen", "Paris-Roubaix",
                    "Liège-Bastogne-Liège", "Il Lombardia"])
races = lazy.with_columns(pl.col("race").cast(Monument)).collect()
print(races.filter(pl.col("year") == 2026).sort("race").select("race", "date", "winner", "nat"))

# %% [markdown]
# The honour roll, as Wikipedia prints it: one column per Monument, first and latest
# win, and a rank that shares places on ties. There is no pivot here: each Monument
# column is a conditional sum, one expression per race, built in a loop over the
# categories. `rank("min")` gives tied riders the same place.

# %%
# id: s03_roll
short = {"Milano-Sanremo": "MSR", "Ronde van Vlaanderen": "RVV", "Paris-Roubaix": "PR",
         "Liège-Bastogne-Liège": "LBL", "Il Lombardia": "IL"}
roll = (races.group_by("winner")
        .agg(pl.col("nat").first(), pl.col("year").min().alias("first"),
             pl.col("year").max().alias("latest"),
             *[(pl.col("race") == m).sum().alias(short[m]) for m in Monument.categories],
             pl.len().alias("total"))
        .with_columns(pl.col("total").rank("min", descending=True).alias("rank"))
        .sort("total", "first", descending=[True, False]))
with pl.Config(tbl_cols=12):
    print(roll.select("rank", pl.exclude("rank")).head(12))

# %% [markdown]
# ## 4. Gerbi or Seixas?
#
# [inrng](https://inrng.com/2026/10/lombardia-2026-review/): "Seixas becomes the youngest ever winner of Lombardia, pipping Giovanni Gerbi
# who was also 20 when he won the inaugural edition in 1905." Both were 20. Subtracting
# two dates gives a `Duration`, and `totalDays` settles it.

# %%
# id: s04_gerbi
age = (pl.col("date") - pl.col("born")).alias("age")
print(races.filter(pl.col("winner").is_in(["Giovanni Gerbi", "Paul Seixas"]))
      .select("year", "winner", "born", "date", age, age.dt.total_days().alias("days")))

# %% [markdown]
# ## 5. The youngest, everywhere
#
# The youngest winner of each Monument, using a window over the race. Seixas is the
# youngest winner of any Monument since Rik Van Steenbergen in 1944.

# %%
# id: s05_youngest
with_age = races.with_columns(days=age.dt.total_days()).drop_nulls("days")
print(with_age.filter(pl.col("days") == pl.col("days").min().over("race"))
      .sort("race").select("race", "year", "winner", "days"))
print(with_age.sort("days").head(5).select("race", "year", "winner", "days"))

# %% [markdown]
# ## 6. Teenagers at the Tour
#
# [inrng's Tour preview](https://inrng.com/2026/07/tour-de-france-preview-2026/): Seixas is "the youngest rider to start the Tour de France since 1937". To check
# that, we need every starter, not only the winners. Wikipedia has a start list for each
# of the 113 editions: 16,438 starters, with a birth date for 94% of them (almost all
# since 1930; the early Tours are patchy). Join each starter with the first day of the
# race, subtract, and sort.

# %%
# id: s06_tour
starters = pl.read_csv("data/starters/starters.csv", try_parse_dates=True,
                       schema_overrides={"no": pl.String})
editions = pl.read_csv("data/starters/editions.csv", try_parse_dates=True)
ages = (starters.filter(pl.col("dns") == 0)
        .join(editions.select("year", "start_date"), on="year")
        .with_columns(age=(pl.col("start_date") - pl.col("born")).dt.total_days()))
print(ages.filter(pl.col("year") >= 1930).sort("age", nulls_last=True)
      .select("year", "name", "born", "age").head(5))

# %% [markdown]
# The start lists say since 1931, not 1937: Fabio Battesini rode the 1931 Tour at
# 7,071 days old, 152 days younger than Seixas. Then the nulls speak. Before 1940, a few
# starters per edition have no birth date on Wikipedia, and one of them may be the
# rider inrng had in mind.

# %%
# id: s06_nulls
print(ages.filter(pl.col("year").is_between(1931, 1939))
      .group_by("year").agg(pl.len().alias("starters"),
                            pl.col("born").null_count().alias("no_birth_date"))
      .sort("year"))

# %% [markdown]
# Before 1930 teenagers were common: 43 starters under 20, the youngest Camille Fily in
# 1904 at 17 years and 50 days. Since then there have been six, and Seixas is the
# youngest of them. He finished fourth.

# %% [markdown]
# ## 7. Faster than ever
#
# Wikipedia lists every Tour's distance and winning time as text, like `73h 56′ 26″`.
# String expressions pull the numbers out, a `duration` expression builds the time, and
# the average speed follows. Two surprises on the way: CSV inference guesses integers
# for the distance until it meets `3660.5`, and the early Tours have no time at all
# (they were decided on points), nor do 1999-2005, whose winner was stripped.

# %%
# id: s07_speed
tours = pl.read_csv("data/tour_winners.csv", schema_overrides={"distance_km": pl.Float64})

def race_time(c):
    part = lambda unit: pl.col(c).str.extract(r"(\d+)" + unit, 1).cast(pl.Int64).fill_null(0)
    return pl.when(pl.col(c).is_not_null()).then(
        pl.duration(hours=part("h"), minutes=part("′"), seconds=part("″")))

tours = tours.with_columns(time=race_time("time"), margin=race_time("margin")).with_columns(
    speed=(pl.col("distance_km") / (pl.col("time").dt.total_seconds() / 3600)).round(3))
print(tours.sort("speed", descending=True, nulls_last=True).head(5)
      .select("year", "winner", "distance_km", "time", "speed"))

# %% [markdown]
# 43.887 km/h is a record, but [inrng's Tour review](https://inrng.com/2026/07/tour-de-france-2026-review/) says the record is 43.227 km/h. At 43.227 km/h,
# 73h 56′ 26″ covers 3,196 km, not the 3,245 km Wikipedia lists. Race reports confirm it:
# the riders covered 3,197 km (the route was planned at 3,333 km), so the table's distance
# is wrong, not the clock.

# %%
# id: s07_check
print(tours.filter(pl.col("year") == 2026).select(
    (pl.lit(43.227) * pl.col("time").dt.total_seconds() / 3600).round(1).alias("km_at_43.227")))

# %% [markdown]
# ## 8. 4′ 23″
#
# Polars prints 73h 56′ 26″ as `3d 1h 56m 26s`. Cycling writes time gaps its own way, so
# here is a formatter built from expressions. Vingegaard won Paris-Nice by 4′ 23″, the
# fourth largest margin ever (the three wider ones were all in the 1930s). Tour margins
# can be much smaller.

# %%
# id: s08_gaps
def gap(c):
    s = pl.col(c).dt.total_seconds()
    two = lambda e: e.cast(pl.String).str.zfill(2)
    hms = pl.format("{}h {}′ {}″", s // 3600, two(s % 3600 // 60), two(s % 60))
    ms = pl.format("{}′ {}″", s // 60, two(s % 60))
    return pl.when(s >= 3600).then(hms).otherwise(ms)

print(tours.drop_nulls("margin").sort("margin").head(5)
      .select("year", "winner", gap("margin").alias("margin"), gap("time").alias("time")))
print(pl.select(paris_nice=pl.duration(minutes=4, seconds=23)).select(gap("paris_nice")))

# %% [markdown]
# ## 9. The same band every night
#
# The Giro's general classification after every stage, from Wikipedia. The leader's line
# holds a total time, everyone else's a gap (`+ 5' 22"`). Vingegaard took pink on stage
# 14 and kept it; behind him the band took a while to settle: Eulálio, then Gall, with
# Arensman and finally Hindley third. Gall's final gap: 5′ 22″.

# %%
# id: s09_giro
giro = pl.read_csv("data/giro_gc_2026.csv")
giro = giro.with_columns(
    date=pl.col("date").str.to_date("%d %B %Y"),
    gap=pl.when(pl.col("rank") == 1).then(pl.duration(seconds=0)).otherwise(
        pl.duration(minutes=pl.col("time").str.extract(r"(\d+)'", 1).cast(pl.Int64).fill_null(0),
                    seconds=pl.col("time").str.extract(r"(\d+)\"", 1).cast(pl.Int64).fill_null(0))),
)
podium = (giro.filter(pl.col("rank") <= 3).sort("stage", "rank")
          .group_by("stage", "date").agg(pl.col("rider").str.join(" / ").alias("podium"))
          .sort("stage"))
print(podium.tail(10))
print(giro.filter(pl.col("rider").is_in(["Felix Gall", "Jai Hindley"]), pl.col("stage") >= 12)
      .group_by("rider").agg(pl.col("rank").min().alias("best"), pl.col("rank").max().alias("worst"),
                             gap("gap").last().alias("final_gap")).sort("rider"))

# %% [markdown]
# ## 10. Set your alarm
#
# The season starts in Adelaide. [inrng's preview](https://inrng.com/2026/01/2026-tour-down-under-preview/) gives each stage's finish time in local
# time, CET and US Eastern, and admits that stage 1 is scheduled for 2.03pm, not 2pm.
# With `tryParseDates`, "14:03" becomes a time of day; combining it with the date and an
# IANA zone gives a real instant, and converting zones checks inrng's arithmetic.

# %%
# id: s10_alarm
tdu = pl.read_csv(io.StringIO("""stage,date,finish,inrng_cet,inrng_est
Prologue,2026-01-20,20:30,11:00,05:00
1,2026-01-21,14:03,16:33,22:32
2,2026-01-22,15:02,05:32,23:32
4,2026-01-24,13:22,03:52,21:52
"""), try_parse_dates=True)
finish = pl.col("date").dt.combine(pl.col("finish")).dt.replace_time_zone("Australia/Adelaide")
print(tdu.select(
    "stage",
    finish.dt.convert_time_zone("Europe/Paris").alias("cet"),
    (finish.dt.convert_time_zone("Europe/Paris").dt.time() == pl.col("inrng_cet")).alias("cet_ok"),
    finish.dt.convert_time_zone("America/New_York").alias("est"),
    (finish.dt.convert_time_zone("America/New_York").dt.time() == pl.col("inrng_est")).alias("est_ok"),
))

# %% [markdown]
# Stage 1's CET time is a typo for 4.33am, and its US time is a minute off. Prologue and
# the other stages check out.
#
# ## 11. The smudged result sheet
#
# Not every source writes dates the same way. A strict parse stops at the first odd
# row with a specific error, which the post catches; a lenient one turns it into null.

# %%
# id: s11_smudged
smudged = pl.DataFrame({"race": ["Paris-Roubaix", "Amstel Gold Race", "La Flèche Wallonne"],
                        "date": ["12 April 2026", "19 April 2026", "22/04/2026"]})
try:
    smudged.with_columns(pl.col("date").str.to_date("%d %B %Y"))
except pl.exceptions.InvalidOperationError as e:
    print(type(e).__name__, "-", str(e).splitlines()[0])
print(smudged.with_columns(pl.col("date").str.to_date("%d %B %Y", strict=False)))

# %% [markdown]
# *(Nim note: Polars raises `InvalidOperationError` here, not `ComputeError` as the API
# doc guessed. The error type is whatever Polars says; the post shows the real one.)*
#
# ## 12. Finale: one season, one strip
#
# [inrng](https://inrng.com/2026/10/lombardia-2026-review/) counted "only 49 days of racing" for Seixas this year, across World Tour and
# smaller races. Our tables can't recount that: they list winners, not start lists. What
# they can show is the World Tour around him. A `dateRange` gives one row per day of 2026,
# and a cross join keeps the days that fall between a race's start and end: the racing
# days of the calendar, month by month. Next to them, the days each rider won something:
# a one-day race or a stage.

# %%
# id: s12_strip
year = pl.select(day=pl.date_range(dt.date(2026, 1, 1), dt.date(2026, 12, 31), "1d"))
days = year.join(season, how="cross").filter(pl.col("day").is_between("start", "end"))
won = pl.concat([
    season.filter(pl.col("start") == pl.col("end")).select("winner", day="start"),
    stages.select("winner", day="date"),
])
per_month = (
    days.group_by(pl.col("day").dt.month().alias("month")).agg(pl.len().alias("race_days"))
    .join(won.group_by(pl.col("day").dt.month().alias("month")).agg(
              (pl.col("winner") == "Paul Seixas").sum().alias("seixas_wins"),
              (pl.col("winner") == "Tadej Pogačar").sum().alias("pogacar_wins")),
          on="month", how="left")
    .sort("month"))
print(per_month)
print(days.select(pl.len().alias("world_tour_race_days"), pl.col("day").n_unique().alias("calendar_days")))

# %% [markdown]
# Pogačar won the Tour, three Monuments and 15 stages, with wins in six straight months,
# March to August. Seixas won one Monument at 20
# years and 16 days, and finished fourth in his first Tour at 19. [inrng](https://inrng.com/2026/10/lombardia-2026-review/) ends its
# Lombardia review on the question everyone is asking: is the goal now to dethrone
# Pogačar? Next season's data will tell.
