"""Expected outputs for docs/blog/bear_census.nim, computed with py-polars.

Each function here repeats one Nim code block of the post with py-polars and
writes what that block prints to expected/<scene>.txt. The post was drafted
against these outputs before Nanuq 0.2 existed; now that it runs, rendering it
fails when a Nanuq output differs. Run from this folder: python3 -I expected.py
"""
import os, io, contextlib
import polars as pl
import polars.selectors as cs

pl.Config(tbl_rows=25, tbl_cols=12, tbl_width_chars=120, tbl_hide_dataframe_shape=False)
os.chdir(os.path.dirname(os.path.abspath(__file__)))
os.makedirs("expected", exist_ok=True)

def short(t):  # Nanuq's `$` on a DataType prints Nanuq code: Int64, String, ...
    simple = str(t)
    if "(" in simple:
        raise ValueError(f"no Nanuq name for {simple} in this scene")
    return simple

def first_line(e):
    return str(e).splitlines()[0]

def scene(name):
    def deco(f):
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            f()
        with open(f"expected/{name}.txt", "w") as fh:
            fh.write(buf.getvalue().rstrip("\n") + "\n")
        return f
    return deco

WEEKS = [f"data/logs/{w}" for w in sorted(os.listdir("data/logs"))]
NULLS = ["?"]
OVERRIDES = {"bears": pl.String, "weight_kg": pl.Float64}

@scene("s01_first_week")
def _():
    week1 = pl.read_csv(WEEKS[0])
    print(week1)

@scene("s02_scan_glob")
def _():
    try:
        pl.scan_csv("data/logs/*.csv", null_values=NULLS, schema_overrides=OVERRIDES).collect()
    except Exception as e:
        print(first_line(e))

season = pl.concat([pl.scan_csv(w, null_values=NULLS, schema_overrides=OVERRIDES) for w in WEEKS],
                   how="diagonal")

@scene("s03_scan_concat")
def _():
    for name, t in season.collect_schema().items():
        print(f"{name:<15}{short(t)}")

@scene("s04_strict")
def _():
    try:
        season.select(pl.col("bears").cast(pl.Int64)).collect()
    except Exception as e:
        print(first_line(e))

log = season.cast({"bears": pl.Int64, "cubs": pl.UInt8, "collared": pl.Boolean},
                  strict=False).collect()

@scene("s05_cast")
def _():
    print("@[" + ", ".join(short(t) for t in log.dtypes) + "]")
    print("bear counts we couldn't read:", log["bears"].null_count())

tidy = log.unique(maintain_order=True).with_row_index("report", offset=1)

@scene("s06_tidy")
def _():
    print(f"reports: {log.height} radioed, {tidy.height} after unique")
    print(tidy.select("report", "week", "station", "ranger", "bears").tail(3))

@scene("s07_fill")
def _():
    print(tidy.select("report", "station", "ranger",
                      pl.col("ranger").fill_null(strategy="forward").alias("naive"),
                      pl.col("ranger").forward_fill().over("station").alias("per_station"))
              .filter(pl.col("ranger").is_null()))

filled = tidy.with_columns(pl.col("ranger").forward_fill().over("station"))

checked = filled.with_columns(
    pl.when(pl.col("weight_kg").is_between(150, 800)).then(pl.col("weight_kg")).alias("weight_kg"),
    pl.col("station").is_in(["Longyearbyen", "Barentsburg"]).alias("near_people"),
)

@scene("s08_sanity")
def _():
    print(checked.filter(pl.col("station") == "Ny-Alesund")
                 .select("report", "station", "weight_kg", "near_people"))

stations = pl.read_csv("data/stations.csv")

@scene("s09_join_validate")
def _():
    try:
        checked.join(stations, on="station", how="left", validate="m:1")
    except Exception as e:
        print(first_line(e))

@scene("s10_join_anti")
def _():
    print(checked.join(stations, on="station", how="anti").select("station").unique())

located = checked.join(stations.unique(maintain_order=True), on="station", how="left",
                       validate="m:1", maintain_order="left")

sized = located.with_columns(
    pl.when(pl.col("weight_kg").is_null()).then(pl.lit("unweighed"))
      .when(pl.col("weight_kg") < 200).then(pl.lit("slim"))
      .when(pl.col("weight_kg") < 450).then(pl.lit("solid"))
      .otherwise(pl.lit("chonk")).alias("size"),
    (pl.col("ringed") + 10 * pl.col("bearded")).alias("seal_eq"),
)

@scene("s11_size")
def _():
    print(sized.select("station", "weight_kg", "size", "ringed", "bearded", "seal_eq")
               .head(8))

@scene("s12_over")
def _():
    print(sized.filter(pl.col("station") == "Hornsund").select(
        "week", "weight_kg",
        (pl.col("weight_kg") - pl.col("weight_kg").mean().over("station")).round(1)
            .alias("vs_station")))

@scene("s13_selectors")
def _():
    print(sized.group_by("station").agg(
            cs.numeric().exclude("report", "week", "cubs", "ringed", "bearded", "lat", "lon")
              .mean().round(1).name.suffix("_mean"))
          .sort("station"))

@scene("s14_quantile")
def _():
    print(sized.select(
        pl.col("weight_kg").median().alias("median"),
        pl.col("weight_kg").quantile(0.9).alias("p90"),
        pl.col("weight_kg").std().round(1).alias("std")))

report = (sized.sort(["weight_kg", "week"], descending=[True, False], nulls_last=True)
               .select("week", "station", "ranger", "bears", "weight_kg", "size", "seal_eq"))

@scene("s15_report")
def _():
    print(report)

@scene("s16_spot")
def _():
    print(report.sample(3, seed=42))

@scene("s17_norsk")
def _():
    norsk = report.rename({"week": "uke", "station": "stasjon", "bears": "isbjorner",
                           "weight_kg": "vekt_kg", "size": "storrelse", "seal_eq": "sel_ekv"})
    norsk.write_csv("governor.csv", separator=";", decimal_comma=True)
    with open("governor.csv") as fh:
        print("".join(fh.readlines()[:4]).rstrip())
    os.remove("governor.csv")

dens = pl.read_csv("data/dens.csv")

@scene("s18_dens")
def _():
    print(dens.with_columns(
            pl.when(pl.col("ice_day") < 335).then(pl.lit("before December"))
              .otherwise(pl.lit("December or later")).alias("ice_arrived"))
          .group_by("ice_arrived").agg(
            pl.col("year").len().alias("years"),
            pl.col("dens").mean().round(1).alias("dens"),
            pl.col("cub_kg").mean().round(2).alias("cub_kg"))
          .sort("ice_arrived", descending=True))

for f in sorted(os.listdir("expected")):
    print("===", f)
    print(open(f"expected/{f}").read())
