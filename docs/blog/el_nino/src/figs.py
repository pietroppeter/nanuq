"""Plotly figures for the El Niño explainer. The post's cells compute frames with Polars and
pass them here, so the Nanuq code stays in the post. Only scatter, bar and heatmap traces,
shapes and annotations are used, so that the Nim version can redo each one with nim-plotly."""
import numpy as np
import plotly.graph_objects as go
import plotly.io as pio
import polars as pl

pio.renderers.default = "notebook"  # plotly.js inlined once: the page works offline

SURFACE = "#fcfcfb"
INK, INK2, MUTED, GRID = "#1f1f1e", "#5c5b57", "#8a8984", "#e6e5e1"
BLUE, ORANGE, AQUA, YELLOW = "#2a78d6", "#eb6834", "#1baf7a", "#eda100"
WARM, COOL, GREY = "#d1453f", "#2a78d6", "#c9c8c3"
LAND = "#d9d7d0"
CONFIG = dict(displaylogo=False, modeBarButtonsToRemove=["toImage"])  # no download button: artifact pages cannot download
DIVERGING = [[0, "#0d366b"], [0.2, "#256abf"], [0.38, "#86b6ef"], [0.5, "#f0efec"],
             [0.62, "#f2a3a0"], [0.8, "#d1453f"], [1, "#7f1d1d"]]
SEQUENTIAL = [[0, "#0d366b"], [0.25, "#3987e5"], [0.45, "#cde2fb"], [0.6, "#fbe3c4"],
              [0.75, "#f0a35e"], [0.9, "#d1453f"], [1, "#7f1d1d"]]
BOXES = {  # name: (lon west, lon east, lat south, lat north), lon in degrees east
    "Niño 4": (160, 210, -5, 5), "Niño 3.4": (190, 240, -5, 5),
    "Niño 3": (210, 270, -5, 5), "Niño 1+2": (270, 280, -10, 0),
}


SAVE_PATH = None  # expected.py sets this to keep each figure as JSON for the Nim post


def _show(fig):
    if SAVE_PATH:
        with open(SAVE_PATH, "w") as f:
            f.write(fig.to_json())
    else:
        fig.show(config=CONFIG)


def _layout(fig, title, height=380, source=None, **kw):
    fig.update_layout(
        title=dict(text=f"<b>{title}</b>", x=0.01, xanchor="left", font=dict(size=15, color=INK)),
        height=height, margin=dict(l=60, r=30, t=50, b=55 if source else 40),
        paper_bgcolor=SURFACE, plot_bgcolor=SURFACE,
        font=dict(family="Inter, system-ui, sans-serif", size=12, color=INK2),
        hoverlabel=dict(bgcolor="white", font_color=INK), **{"showlegend": False, **kw})
    fig.update_xaxes(gridcolor=GRID, zeroline=False, linecolor=GRID)
    fig.update_yaxes(gridcolor=GRID, zeroline=False, linecolor=GRID)
    if source:
        fig.add_annotation(text=source, xref="paper", yref="paper", x=0, y=-0.17,
                           xanchor="left", showarrow=False, font=dict(size=10, color=MUTED))
    return fig


def _months(df):
    """Decimal year at mid-month, for monthly series on a continuous axis."""
    return (df["year"] + (df["month"] - 0.5) / 12).to_list()


# ---------------------------------------------------------------- maps

def _lon_label(t):
    return f"{t}°E" if t < 180 else ("180°" if t == 180 else f"{360 - t}°W")


def _map(fig, field, value, colorscale, zmin, zmax, row=None, col=None, colorbar=None,
         hover="%{z:.1f} °C", boxes=("Niño 3.4",)):
    """A heatmap of `value` on the lat/lon grid of `field` (one row per grid point)."""
    grid = field.pivot(on="lon", index="lat", values=value).sort("lat")
    lons = [float(c) for c in grid.columns[1:]]
    kw = dict(row=row, col=col) if row else {}
    fig.add_trace(go.Heatmap(
        x=lons, y=grid["lat"].to_list(), z=grid.drop("lat").rows(), colorscale=colorscale,
        zmin=zmin, zmax=zmax, zmid=0 if zmin < 0 else None, showscale=colorbar is not None,
        colorbar=colorbar, hovertemplate="%{x}°E, %{y}°<br>" + hover + "<extra></extra>"), **kw)
    ticks = [120, 150, 180, 210, 240, 270]
    fig.update_xaxes(range=[120, 290], tickvals=ticks, ticktext=[_lon_label(t) for t in ticks],
                     showgrid=False, constrain="domain", **kw)
    fig.update_yaxes(range=[-30, 30], tickvals=[-30, -15, 0, 15, 30],
                     ticktext=["30°S", "15°S", "0°", "15°N", "30°N"], showgrid=False, **kw)
    for b in boxes:
        w, e, s, n = BOXES[b]
        fig.add_shape(type="rect", x0=w, x1=e, y0=s, y1=n, line=dict(color=INK, width=1.5), **kw)
        fig.add_annotation(x=(w + e) / 2, y=n + 2.5 if b != "Niño 1+2" else s - 3, text=f"<b>{b}</b>",
                           showarrow=False, font=dict(size=10, color=INK), **kw)


def pacific_normal():
    """The Pacific in a normal year: 1991-2020 mean SST, with the Niño 3.4 box."""
    normal = pl.read_csv("data/pacific_normal.csv")
    fig = go.Figure()
    _map(fig, normal, "sst", SEQUENTIAL, 14, 30, colorbar=dict(title="°C", len=0.8))
    for x, y, t, c in [(145, 4, "warm pool", "white"), (255, -9, "cold tongue", INK)]:
        fig.add_annotation(x=x, y=y, text=f"<b>{t}</b>", showarrow=False, font=dict(color=c, size=13))
    fig.add_annotation(x=205, y=11, ax=258, ay=11, axref="x", ayref="y", text="", showarrow=True,
                       arrowhead=2, arrowwidth=2, arrowcolor=INK)
    fig.add_annotation(x=231, y=14, text="trade winds", showarrow=False, font=dict(color=INK))
    fig.update_yaxes(scaleanchor="x")
    _layout(fig, "The Pacific in a normal year: sea surface temperature, 1991-2020 mean",
            height=420, source="Data: NOAA ERSSTv5. Land in grey.")
    fig.update_layout(plot_bgcolor=LAND)
    _show(fig)


def anomaly_maps(months, titles, ncols=None, boxes=("Niño 3.4",), title=None):
    """Small multiples of SST anomaly maps on one shared diverging scale (±4 °C)."""
    from plotly.subplots import make_subplots
    anomaly = pl.read_csv("data/pacific_anomaly.csv")
    n = len(months); ncols = ncols or n; nrows = int(np.ceil(n / ncols))
    fig = make_subplots(rows=nrows, cols=ncols, subplot_titles=titles,
                        horizontal_spacing=0.05, vertical_spacing=0.14)
    for i, mo in enumerate(months):
        r, c = i // ncols + 1, i % ncols + 1
        _map(fig, anomaly.filter(pl.col("month") == mo), "anomaly", DIVERGING, -4, 4,
             row=r, col=c, boxes=boxes,
             hover="%{z:+.1f} °C vs normal",
             colorbar=dict(title="°C", len=0.7, tickvals=[-4, -2, 0, 2, 4]) if i == 0 else None)
    for a in fig.layout.annotations[:n]:
        a.update(x=a.x, font=dict(size=12, color=INK))
    _layout(fig, title or "Sea temperature compared with normal", height=230 * nrows + 130,
            source="Data: NOAA ERSSTv5. Red: warmer than the 1991-2020 normal for that month; blue: cooler.")
    fig.update_layout(plot_bgcolor=LAND)
    _show(fig)


def walker_schematic():
    """Cross-section along the equator, normal conditions vs El Niño, drawn with shapes."""
    from plotly.subplots import make_subplots
    fig = make_subplots(rows=1, cols=2, subplot_titles=["Normal conditions", "El Niño"],
                        horizontal_spacing=0.04)
    for col, nino in [(1, False), (2, True)]:
        k = dict(row=1, col=col)
        tw, te = (-2.6, -0.6) if not nino else (-1.7, -1.4)  # thermocline depth west, east
        poly = lambda pts, color: fig.add_shape(
            type="path", path="M " + " L ".join(f"{x},{y}" for x, y in pts) + " Z",
            fillcolor=color, line=dict(width=0), layer="below", **k)
        poly([(0.6, 0), (9.4, 0), (9.4, te), (0.6, tw)], "#f2a3a0")   # warm layer
        poly([(0.6, tw), (9.4, te), (9.4, -4), (0.6, -4)], "#9ec5f4")  # cold deep water
        poly([(0, -4), (0.6, -4), (0.6, 0.3), (0, 0.6)], LAND)
        poly([(9.4, -4), (10, -4), (10, 1.4), (9.4, 0.4)], LAND)
        fig.add_shape(type="line", x0=0.6, y0=tw, x1=9.4, y1=te, line=dict(color=INK2, dash="dash", width=1), **k)
        fig.add_annotation(x=5, y=(tw + te) / 2 - 0.5, text="thermocline", showarrow=False,
                           font=dict(size=10, color=INK2), **k)
        cx = 2.2 if not nino else 5.8  # where the air rises and rains
        fig.add_shape(type="circle", x0=cx - 1.2, x1=cx + 1.2, y0=2.3, y1=3.4, fillcolor=GREY,
                      line=dict(width=0), **k)
        for x in np.linspace(cx - 0.8, cx + 0.8, 5):
            fig.add_shape(type="line", x0=x, y0=2.2, x1=x - 0.15, y1=1.6, line=dict(color=COOL, width=1.5), **k)
        fig.add_annotation(x=cx, y=3.85, text="rain", showarrow=False, font=dict(size=11), **k)
        arrow = lambda x0, y0, x1, y1: fig.add_annotation(
            x=x1, y=y1, ax=x0, ay=y0, axref=f"x{col if col > 1 else ''}", ayref=f"y{col if col > 1 else ''}",
            text="", showarrow=True, arrowhead=2, arrowwidth=1.8, arrowcolor=INK, **k)
        if not nino:
            arrow(8.6, 0.6, 3.6, 0.6); arrow(3.4, 1.0, 3.4, 2.4); arrow(3.6, 4.2, 8.6, 4.2)
            arrow(8.9, 4.0, 8.9, 1.0); arrow(8.9, -2.8, 8.9, -0.9)
            fig.add_annotation(x=6, y=1.0, text="strong trade winds", showarrow=False, **k)
            fig.add_annotation(x=7.4, y=3.0, text="dry, sinking air", showarrow=False,
                               font=dict(size=10, color=INK2), **k)
            fig.add_annotation(x=7.4, y=-1.9, text="cold water wells up", showarrow=False,
                               font=dict(size=10, color="#0d366b"), **k)
        else:
            arrow(3.0, 0.6, 4.4, 0.6); arrow(8.6, 0.6, 7.2, 0.6)
            fig.add_annotation(x=5.8, y=-0.6, text="warm water spreads east", showarrow=False,
                               font=dict(size=10, color="#7f1d1d"), **k)
            fig.add_annotation(x=1.6, y=1.2, text="drought", showarrow=False, **k)
            fig.add_annotation(x=5.8, y=1.0, text="weak trade winds", showarrow=False, **k)
        fig.add_annotation(x=0.3, y=-4.5, text="Indonesia", showarrow=False, font=dict(size=10), **k)
        fig.add_annotation(x=9.5, y=-4.5, text="South America", showarrow=False, font=dict(size=10), **k)
    fig.update_xaxes(range=[0, 10], visible=False)
    fig.update_yaxes(range=[-4.8, 4.6], visible=False)
    _layout(fig, "What changes during El Niño (a slice along the equator)", height=360,
            source="Schematic, not to scale. After NOAA PMEL's El Niño diagrams.")
    _show(fig)


# ---------------------------------------------------------------- charts

def oni_bars(oni):
    """ONI as bars: red at or above +0.5, blue at or below -0.5, grey in between."""
    v = oni["oni"].to_list()
    colors = [WARM if x >= 0.5 else COOL if x <= -0.5 else GREY for x in v]
    fig = go.Figure(go.Bar(x=_months(oni), y=v, marker=dict(color=colors, line=dict(width=0)),
                           customdata=list(zip(oni["season"].to_list(), oni["year"].to_list())),
                           hovertemplate="%{customdata[0]} %{customdata[1]}: %{y:+.1f} °C<extra></extra>"))
    fig.update_layout(bargap=0)
    for y in (0.5, -0.5):
        fig.add_hline(y=y, line=dict(color=INK2, width=1, dash="dot"))
    for x, y, t in [(1983, 2.4, "1982-83"), (1998, 2.65, "1997-98"), (2016, 2.85, "2015-16"), (2026.6, 2.45, "2026")]:
        fig.add_annotation(x=x, y=y, text=t, showarrow=False, font=dict(size=11))
    fig.update_yaxes(title="ONI, °C", range=[-2.3, 3.1])
    fig.update_xaxes(range=[1949.5, 2027.5])
    _layout(fig, "Oceanic Niño Index 1950-2026: El Niño in red, La Niña in blue",
            source="Data: NOAA CPC. Dotted lines at ±0.5 °C.")
    _show(fig)


def growth(side):
    """Each event's ONI by season since onset; the last column is drawn on top, thicker."""
    cols = [c for c in side.columns if c != "season_no"]
    palette = [GREY, BLUE, AQUA, ORANGE, WARM]
    fig = go.Figure()
    for c, color in zip(cols, palette):
        name = "2015-16" if c == "2014" else c
        fig.add_trace(go.Scatter(x=side["season_no"].to_list(), y=side[c].to_list(), name=name,
                                 mode="lines+markers+text", line=dict(color=color, width=3.5 if c == cols[-1] else 2),
                                 marker=dict(size=7), text=[""] * 7 + [name] if c != cols[-1] else [""] * 4 + [name],
                                 textposition="middle right",
                                 hovertemplate=name + ", season %{x}: %{y:.1f} °C<extra></extra>"))
    fig.update_xaxes(title="season since the event began", range=[0.7, 9.0], dtick=1)
    fig.update_yaxes(title="ONI, °C")
    _layout(fig, "2026 is growing faster than any El Niño since 1950", height=400, showlegend=True,
            legend=dict(orientation="h", y=1.08, x=0))
    _show(fig)


def two_rulers(oni, roni, since=1995):
    fig = go.Figure()
    for df, color, name in [(oni, GREY, "ONI (official until January 2026)"),
                            (roni, WARM, "RONI (official since February 2026)")]:
        d = df.filter(pl.col("year") >= since)
        fig.add_trace(go.Scatter(x=_months(d), y=d["oni"].to_list(), name=name, mode="lines",
                                 line=dict(color=color, width=2),
                                 customdata=list(zip(d["season"].to_list(), d["year"].to_list())),
                                 hovertemplate=name.split(" ")[0] + " %{customdata[0]} %{customdata[1]}: %{y:+.1f}<extra></extra>"))
    fig.add_hline(y=0.5, line=dict(color=INK2, width=1, dash="dot"))
    fig.update_yaxes(title="°C"); fig.update_xaxes(range=[since, 2027])
    _layout(fig, "Two rulers for the same ocean", height=360, showlegend=True,
            legend=dict(orientation="h", y=1.1, x=0), hovermode="x unified")
    _show(fig)


def soi_vs_oni(both, since=1980):
    """Two stacked panels, one per measure (never a second y-axis)."""
    from plotly.subplots import make_subplots
    d = both.filter(pl.col("year") >= since)
    t = _months(d)
    fig = make_subplots(rows=2, cols=1, shared_xaxes=True, vertical_spacing=0.12,
                        subplot_titles=["Sea: Niño 3.4 anomaly, °C (3-month mean)",
                                        "Air: Southern Oscillation Index (3-month mean), its mirror image"])
    for r, ycol, warm_if_pos in [(1, "mine", True), (2, "soi3", False)]:
        v = d[ycol].to_list()
        colors = [WARM if (x >= 0) == warm_if_pos else COOL for x in v]
        fig.add_trace(go.Bar(x=t, y=v, marker=dict(color=colors, line=dict(width=0)),
                             hovertemplate="%{x:.1f}: %{y:+.2f}<extra></extra>"), row=r, col=1)
    fig.update_layout(bargap=0)
    for a in fig.layout.annotations:
        a.update(x=0, xanchor="left", font=dict(size=12, color=INK))
    _layout(fig, "Ocean and atmosphere move together", height=440,
            source="Data: NOAA CPC. Red marks the El Niño side of each index.")
    fig.update_xaxes(range=[since, 2027])
    _show(fig)


def box_lines(boxes, since=2014):
    d = boxes.filter(pl.col("year") >= since)
    fig = go.Figure()
    for c, color, name in [("nino12_anom", ORANGE, "Niño 1+2 (coast of Peru)"),
                           ("nino34_anom", WARM, "Niño 3.4 (central Pacific)"),
                           ("nino4_anom", BLUE, "Niño 4 (west)")]:
        fig.add_trace(go.Scatter(x=_months(d), y=d[c].to_list(), name=name, mode="lines",
                                 line=dict(color=color, width=2),
                                 hovertemplate=name.split(" (")[0] + ": %{y:+.2f} °C<extra></extra>"))
    for x, t in [(2017.2, "2017: coast only"), (2023.2, "2023: coast first")]:
        fig.add_annotation(x=x, y=2.9, text=t, showarrow=False, font=dict(size=11))
    fig.update_yaxes(title="°C vs normal"); fig.update_xaxes(range=[since, 2027])
    _layout(fig, "Three of the four boxes, 2014-2026", height=380, showlegend=True,
            legend=dict(orientation="h", y=1.1, x=0), hovermode="x unified",
            source="Data: NOAA CPC (OISST v2.1).")
    _show(fig)


def piura(years):
    d = years.with_columns(y=pl.col("date").dt.year())
    full = d["days"] >= 300
    fig = go.Figure(go.Bar(x=d["y"].to_list(), y=d["rain_mm"].to_list(),
                           marker=dict(color=[BLUE if f else "#b7d3f6" for f in full.to_list()]),
                           customdata=d["days"].to_list(),
                           hovertemplate="%{x}: %{y:,.0f} mm (%{customdata} days reported)<extra></extra>"))
    for yr in (1983, 1998, 2017):
        v = d.filter(pl.col("y") == yr)["rain_mm"].item()
        fig.add_annotation(x=yr, y=v, text=str(yr), showarrow=False, yshift=12)
    fig.update_yaxes(title="rain per year, mm")
    _layout(fig, "Piura, Peru: rain in a desert city", height=360,
            source="Data: NOAA GHCN-Daily, Piura airport. Light bars: fewer than 300 days reported that year.")
    _show(fig)


def world(yearly, smooth, records):
    s = smooth.with_columns(year=pl.col("date").dt.year(), month=pl.col("date").dt.month())
    fig = go.Figure()
    fig.add_trace(go.Scatter(x=_months(s), y=s["ewm12"].to_list(), name="monthly, smoothed (ewmMean, span 12)",
                             mode="lines", line=dict(color="#9ec5f4", width=1.2), hovertemplate="%{y:.2f} °C<extra></extra>"))
    fig.add_trace(go.Scatter(x=(yearly["year"] + 0.5).to_list(), y=yearly["temp"].to_list(), name="yearly mean",
                             mode="lines", line=dict(color=BLUE, width=2), hovertemplate="%{x:.0f}: %{y:.2f} °C<extra></extra>"))
    fig.add_trace(go.Scatter(x=(records["year"] + 0.5).to_list(), y=records["temp"].to_list(), name="record year",
                             mode="markers", marker=dict(color=WARM, size=8, line=dict(color=SURFACE, width=2)),
                             hovertemplate="record %{x:.0f}: %{y:.2f} °C<extra></extra>"))
    fig.update_yaxes(title="°C vs 1951-1980"); fig.update_xaxes(range=[1880, 2027])
    _layout(fig, "The world's temperature, 1880-2026", height=400, showlegend=True,
            legend=dict(orientation="h", y=1.1, x=0), source="Data: NASA GISS, GISTEMP v4.")
    _show(fig)


def recent(table):
    fig = go.Figure()
    for c, color in zip(["2023", "2024", "2025", "2026"], [AQUA, BLUE, GREY, WARM]):
        fig.add_trace(go.Scatter(x=table["mon"].to_list(), y=table[c].to_list(), name=c,
                                 mode="lines+markers", line=dict(color=color, width=3.5 if c == "2026" else 2),
                                 marker=dict(size=6), hovertemplate=c + ": %{y:.2f} °C<extra></extra>"))
    fig.update_xaxes(tickvals=list(range(1, 13)), ticktext=list("JFMAMJJASOND"))
    fig.update_yaxes(title="°C vs 1951-1980")
    _layout(fig, "Month by month, 2023-2026", height=380, showlegend=True,
            legend=dict(orientation="h", y=1.1, x=0), hovermode="x unified")
    _show(fig)
