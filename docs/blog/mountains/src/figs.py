"""Plotly figures for the mountains explainer. Only scatter, heatmap and bar traces plus
layout shapes/annotations, so that nim-plotly can redraw every one of them.
Set SAVE_PATH to write the figure JSON instead of showing it (used by expected.py)."""
import json
import plotly.graph_objects as go
import polars as pl
import plotly.io as pio
pio.renderers.default = "notebook"

SAVE_PATH = None
TERRAIN = [[0.0, "#2b6c8f"], [0.0001, "#e8eedb"], [0.15, "#c9d6a3"], [0.35, "#b9a173"],
           [0.6, "#8c6d4f"], [0.8, "#d8d2cb"], [1.0, "#ffffff"]]

def _out(fig):
    fig.update_layout(template="plotly_white", margin=dict(l=40, r=20, t=50, b=40))
    if SAVE_PATH:
        open(SAVE_PATH, "w").write(fig.to_json())
    else:
        fig.show()

def _relief(path, zmax):
    r = pl.read_parquet(path)
    lons = r["lon"].unique().sort().to_list(); lats = r["lat"].unique().sort().to_list()
    z = r.sort("lat", "lon")["ele"].clip(-1, None).reshape((len(lats), len(lons))).to_list()
    return go.Heatmap(x=lons, y=lats, z=z, colorscale=TERRAIN, zmin=0, zmax=zmax,
                      showscale=False, hoverinfo="skip")

def _geo_axes(fig, lon_range, lat_range):
    import math
    lat0 = sum(lat_range) / 2
    fig.update_xaxes(range=lon_range, showgrid=False, constrain="domain", ticksuffix="°E")
    fig.update_yaxes(range=lat_range, showgrid=False, scaleanchor="x",
                     scaleratio=1 / math.cos(math.radians(lat0)), constrain="domain", ticksuffix="°N")

def alps_map(peaks):
    fig = go.Figure(_relief("data/relief_alps.parquet", 4800))
    fig.add_trace(go.Scatter(x=peaks["lon"], y=peaks["lat"], mode="markers",
        marker=dict(size=(peaks["height"] - 3900) / 60 + 5, color="#c0392b", line=dict(width=1, color="white")),
        text=peaks["summit"] + " " + peaks["height"].cast(pl.String) + " m", hoverinfo="text", name="4000ers"))
    for name, lon, lat in [("Mont Blanc", 6.865, 45.833), ("Zermatt peaks", 7.75, 46.02),
                           ("Bernese Oberland", 8.0, 46.6), ("Piz Bernina", 9.908, 46.382),
                           ("Barre des Écrins", 6.358, 44.922), ("Gran Paradiso", 7.266, 45.517)]:
        fig.add_annotation(x=lon, y=lat, text=name, showarrow=True, arrowhead=0, ax=30, ay=-25,
                           font=dict(size=11), bgcolor="rgba(255,255,255,0.7)")
    fig.update_layout(title="The 82 Alpine four-thousanders", height=520, showlegend=False)
    _geo_axes(fig, [5.6, 10.6], [44.6, 47.0])
    _out(fig)

COLORS = ["#1f77b4", "#ff7f0e", "#2ca02c", "#d62728", "#9467bd", "#8c564b", "#e377c2", "#17becf"]

def _treks(fig, pts, names):
    for i, trek in enumerate(names):
        g = pts.filter(pl.col("trek") == trek).gather_every(4).with_columns(
            gap=((pl.col("x").diff() ** 2 + pl.col("y").diff() ** 2).sqrt() > 1500).fill_null(False))
        xs, ys = [], []
        for lon, lat, gap in g.select("lon", "lat", "gap").iter_rows():
            if gap: xs.append(None); ys.append(None)
            xs.append(lon); ys.append(lat)
        fig.add_trace(go.Scatter(x=xs, y=ys, mode="lines", name=trek,
                                 line=dict(width=2.5, color=COLORS[i % len(COLORS)])))

def treks_map(pts, peaks):
    west = ["Tour du Mont Blanc", "Walker's Haute Route", "Tour des Combins", "Tour du Cervin",
            "Tour Monte Rosa", "Alta Via 1 Aosta"]
    fig = go.Figure(_relief("data/relief_west.parquet", 4800))
    _treks(fig, pts, west)
    fig.add_trace(go.Scatter(x=peaks["lon"], y=peaks["lat"], mode="markers", name="4000ers",
        marker=dict(size=7, color="#c0392b", symbol="triangle-up", line=dict(width=0.5, color="white")),
        text=peaks["summit"], hoverinfo="text"))
    fig.update_layout(title="Six treks around the highest Alps", height=560,
                      legend=dict(orientation="h", y=-0.12))
    _geo_axes(fig, [6.6, 8.4], [45.55, 46.35])
    _out(fig)

def dolomites_map(pts):
    fig = go.Figure(_relief("data/relief_dolomites.parquet", 3400))
    _treks(fig, pts, ["Alta Via 1 Dolomites", "Alta Via 2 Dolomites"])
    fig.update_layout(title="The Alte Vie 1 and 2 of the Dolomites", height=560,
                      legend=dict(orientation="h", y=-0.12))
    _geo_axes(fig, [11.55, 12.35], [46.1, 46.8])
    _out(fig)

def profile(pts, trek, labels):
    g = (pts.filter(pl.col("trek") == trek)
         .group_by((pl.col("km") / 0.1).floor().alias("bin")).agg(pl.col("ele").mean(), pl.col("km").mean())
         .sort("bin"))
    fig = go.Figure(go.Scatter(x=g["km"], y=g["ele"], mode="lines", fill="tozeroy",
                               line=dict(color="#1f77b4"), name=trek))
    for r in labels.iter_rows(named=True):
        fig.add_annotation(x=r["km"], y=r["ele"], text=r["label"], showarrow=True, arrowhead=0,
                           ax=0, ay=-22, font=dict(size=10))
    fig.update_layout(title=f"{trek}: elevation profile (100 m bins)", xaxis_title="km",
                      yaxis_title="m", yaxis_range=[0, 3000], height=380)
    _out(fig)

LAND = [[0.0, "#cfe3ef"], [0.5, "#cfe3ef"], [0.5, "#ece9e2"], [1.0, "#ece9e2"]]

def world_map(ranges):
    r = pl.read_parquet("data/relief_world.parquet")
    lons = r["lon"].unique().sort().to_list(); lats = r["lat"].unique().sort().to_list()
    land = (r.sort("lat", "lon")["ele"] > 0).cast(pl.Int8).reshape((len(lats), len(lons))).to_list()
    fig = go.Figure(go.Heatmap(x=lons, y=lats, z=land, colorscale=LAND, showscale=False, hoverinfo="skip"))
    bands = [(0, 2000, "#f2c48d", "below 2000 m"), (2000, 4000, "#e08a4c", "2000-4000 m"),
             (4000, 6000, "#b54b2a", "4000-6000 m"), (6000, 9000, "#5e1a0e", "above 6000 m")]
    rows = ranges.filter(pl.col("Feature") != "Ocean")
    for lo, hi, color, label in bands:
        xs, ys = [], []
        for rec in rows.filter(pl.col("Elev_High").is_between(lo, hi, closed="left")).iter_rows(named=True):
            for ring in rec["outline"]:
                xs += [p[0] for p in ring] + [None]; ys += [p[1] for p in ring] + [None]
        fig.add_trace(go.Scatter(x=xs, y=ys, mode="lines", fill="toself", fillcolor=color,
                                 line=dict(width=0.3, color=color), name=label, hoverinfo="skip"))
    fig.update_layout(title="The world's mountain ranges by highest point (GMBA Inventory v2)",
                      height=520, legend=dict(orientation="h", y=-0.08))
    fig.update_xaxes(range=[-180, 180], showgrid=False, constrain="domain")
    fig.update_yaxes(range=[-60, 80], scaleanchor="x", scaleratio=1, showgrid=False, constrain="domain")
    _out(fig)

OFFSETS = {"Mount Everest": (-40, -30), "Lhotse": (45, -35), "Lhotse Shar": (60, 0), "Makalu": (40, 25),
           "Cho Oyu": (-30, -45), "Kanchenjunga": (30, 30), "Shishapangma": (20, -40),
           "Manaslu": (0, -35), "Annapurna I": (-20, 30), "Dhaulagiri": (-50, -25),
           "K2": (-10, -40), "Broad Peak": (60, -30), "Gasherbrum": (70, 0), "Gasherbrum II": (60, 30),
           "Nanga Parbat": (-40, 30)}

def himalaya_map(high):
    fig = go.Figure(_relief("data/relief_himalaya.parquet", 7000))
    fig.add_trace(go.Scatter(x=high["lon"], y=high["lat"], mode="markers", text=high["peak"],
        marker=dict(size=9, color="#c0392b", symbol="triangle-up", line=dict(width=1, color="white")),
        hoverinfo="text", name="8000ers"))
    for r in high.iter_rows(named=True):
        ax, ay = OFFSETS.get(r["peak"], (0, -30))
        fig.add_annotation(x=r["lon"], y=r["lat"], text=r["peak"], ax=ax, ay=ay, showarrow=True,
                           arrowhead=0, arrowwidth=1, font=dict(size=10), bgcolor="rgba(255,255,255,0.75)")
    fig.update_layout(title="The fourteen 8000ers, plus Lhotse Shar", height=480, showlegend=False)
    _geo_axes(fig, [73, 89.5], [26.8, 36.6])
    _out(fig)
