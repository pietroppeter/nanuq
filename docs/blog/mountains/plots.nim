## Plotly figures for "Above 4000", with nim-plotly. The twin of src/figs.py: same
## traces, colours and layout (without Plotly's "plotly_white" template, which only
## Python ships). nim-plotly builds the traces (type, data, mode, name,
## marker, text) and the basic layout (title, size); what it has no field for (gaps in a
## line, fill colours, colour scales as stops, annotations, axis ranges and aspect ratio)
## is added to the JSON it produces.
import std/[json, math, options, sequtils, strutils]
import plotly except Color
import nanuq

const
  Terrain = [(0.0, "#2b6c8f"), (0.0001, "#e8eedb"), (0.15, "#c9d6a3"), (0.35, "#b9a173"),
             (0.6, "#8c6d4f"), (0.8, "#d8d2cb"), (1.0, "#ffffff")]
  Land = [(0.0, "#cfe3ef"), (0.5, "#cfe3ef"), (0.5, "#ece9e2"), (1.0, "#ece9e2")]
  Colors = ["#1f77b4", "#ff7f0e", "#2ca02c", "#d62728", "#9467bd", "#8c564b", "#e377c2", "#17becf"]
  Red = "#c0392b"

proc scale(stops: openArray[(float, string)]): JsonNode =
  result = newJArray()
  for (p, c) in stops: result.add %*[p, c]

proc finish(traces: seq[Trace[float]], title: string, height: int): PlotJson =
  ## The JSON nim-plotly makes, with the white template figs.py uses.
  let p = Plot[float](traces: traces, layout: Layout(title: title, height: height, autosize: true))
  result = p.toPlotJson
  let l = result.layout
  l["title"] = %*{"text": l["title"].getStr, "x": 0.05}
  l["plot_bgcolor"] = %"white"
  l["margin"] = %*{"l": 40, "r": 20, "t": 50, "b": 40}
  for ax in ["xaxis", "yaxis"]:
    if not l.hasKey(ax): l[ax] = newJObject()
    if l[ax].hasKey("autorange"): l[ax].delete("autorange")

proc note(pj: PlotJson, x, y: float, text: string, ax = 30, ay = -25, size = 11) =
  if not pj.layout.hasKey("annotations"): pj.layout["annotations"] = newJArray()
  pj.layout["annotations"].add %*{"x": x, "y": y, "text": text, "showarrow": true,
    "arrowhead": 0, "ax": ax, "ay": ay, "font": {"size": size},
    "bgcolor": "rgba(255,255,255,0.7)"}

proc geoAxes(pj: PlotJson, lon, lat: (float, float)) =
  ## Degrees of longitude shrink by cos(latitude): keep the map's proportions.
  let lat0 = (lat[0] + lat[1]) / 2
  pj.layout["xaxis"] = %*{"range": [lon[0], lon[1]], "showgrid": false, "constrain": "domain",
                          "ticksuffix": "°E"}
  pj.layout["yaxis"] = %*{"range": [lat[0], lat[1]], "showgrid": false, "scaleanchor": "x",
                          "scaleratio": 1 / cos(degToRad(lat0)), "constrain": "domain",
                          "ticksuffix": "°N"}

proc grid(df: DataFrame, value: string): (seq[float], seq[float], seq[seq[float]]) =
  ## A lon/lat grid (one row per point) as heatmap axes and rows of z.
  let wide = df.pivot(on = "lon", index = "lat", values = value).sort("lat")
  let lons = wide.columns[1 .. ^1]
  var z: seq[seq[float]]
  for r in 0 ..< wide.height:
    z.add lons.mapIt(wide[it, r, float])
  (lons.mapIt(parseFloat(it)), wide.toList("lat", float), z)

proc relief(path: string, zmax: float): (Trace[float], JsonNode) =
  ## Terrain heights as a heatmap, sea level and below in blue.
  let r = readParquet(path).select(col.lon, col.lat, col.ele.cast(Float64).clip(lowerBound = -1.0))
  let (xs, ys, zs) = grid(r, "ele")
  (Trace[float](`type`: PlotType.HeatMap, xs: xs, ys: ys, zs: zs),
   %*{"colorscale": scale(Terrain), "zmin": 0, "zmax": zmax, "showscale": false,
      "hoverinfo": "skip"})

proc withStyle(pj: PlotJson, i: int, style: JsonNode) =
  for k, v in style: pj.traces[i][k] = v

proc lineWithGaps(xs, ys: seq[Option[float]]): (JsonNode, JsonNode) =
  ## Plotly breaks a line at null: nim-plotly's float seqs have no null, so the
  ## coordinates go straight into the JSON.
  var jx = newJArray()
  var jy = newJArray()
  for i in 0 ..< xs.len:
    jx.add(if xs[i].isSome: %xs[i].get else: newJNull())
    jy.add(if ys[i].isSome: %ys[i].get else: newJNull())
  (jx, jy)

# ---------------------------------------------------------------- the Alps

proc alpsMap*(peaks: DataFrame): PlotJson =
  let (bg, bgStyle) = relief("data/relief_alps.parquet", 4800)
  let label = peaks.select(format("{} {} m", col.summit, col.height).alias("t")).toList("t", string)
  let sizes = peaks.select(((col.height - 3900) / 60 + 5).alias("s")).toList("s", float)
  let dots = Trace[float](`type`: PlotType.Scatter, mode: PlotMode.Markers, name: "4000ers",
                          xs: peaks.toList("lon", float), ys: peaks.toList("lat", float), text: label)
  result = finish(@[bg, dots], "The 82 Alpine four-thousanders", 520)
  result.withStyle(0, bgStyle)
  result.withStyle(1, %*{"marker": {"size": sizes, "color": Red, "line": {"width": 1, "color": "white"}},
                         "hoverinfo": "text"})
  for (name, lon, lat) in [("Mont Blanc", 6.865, 45.833), ("Zermatt peaks", 7.75, 46.02),
                           ("Bernese Oberland", 8.0, 46.6), ("Piz Bernina", 9.908, 46.382),
                           ("Barre des Écrins", 6.358, 44.922), ("Gran Paradiso", 7.266, 45.517)]:
    result.note(lon, lat, name)
  result.layout["showlegend"] = %false
  result.geoAxes((5.6, 10.6), (44.6, 47.0))

proc trekLines(pts: DataFrame, names: openArray[string]): seq[(string, JsonNode, JsonNode)] =
  ## Every 4th point of each trek; a jump of more than 1.5 km between two of them is a
  ## gap in the mapped route, drawn as a break in the line.
  for name in names:
    let g = pts.filter(col.trek == name).gatherEvery(4)
      .withColumns(((col.x.diff ^ 2 + col.y.diff ^ 2).sqrt > 1500).fillNull(false).alias("gap"))
    var xs, ys: seq[Option[float]]
    for r in g.select(col.lon, col.lat, col.gap).rows(tuple[lon, lat: float, gap: bool]):
      if r.gap:
        xs.add none(float); ys.add none(float)
      xs.add some(r.lon); ys.add some(r.lat)
    let (jx, jy) = lineWithGaps(xs, ys)
    result.add (name, jx, jy)

proc addTreks(pj: PlotJson, pts: DataFrame, names: openArray[string]) =
  for i, (name, jx, jy) in trekLines(pts, names):
    pj.traces.add %*{"type": "scatter", "mode": "lines", "name": name, "x": jx, "y": jy,
                     "line": {"width": 2.5, "color": Colors[i mod Colors.len]}}

proc treksMap*(pts, peaks: DataFrame): PlotJson =
  let (bg, bgStyle) = relief("data/relief_west.parquet", 4800)
  result = finish(@[bg], "Six treks around the highest Alps", 560)
  result.withStyle(0, bgStyle)
  result.addTreks(pts, ["Tour du Mont Blanc", "Walker's Haute Route", "Tour des Combins",
                        "Tour du Cervin", "Tour Monte Rosa", "Alta Via 1 Aosta"])
  result.traces.add %*{"type": "scatter", "mode": "markers", "name": "4000ers",
    "x": peaks.toList("lon", float), "y": peaks.toList("lat", float),
    "text": peaks.toList("summit", string), "hoverinfo": "text",
    "marker": {"size": 7, "color": Red, "symbol": "triangle-up", "line": {"width": 0.5, "color": "white"}}}
  result.layout["legend"] = %*{"orientation": "h", "y": -0.12}
  result.geoAxes((6.6, 8.4), (45.55, 46.35))

proc dolomitesMap*(pts: DataFrame): PlotJson =
  let (bg, bgStyle) = relief("data/relief_dolomites.parquet", 3400)
  result = finish(@[bg], "The Alte Vie 1 and 2 of the Dolomites", 560)
  result.withStyle(0, bgStyle)
  result.addTreks(pts, ["Alta Via 1 Dolomites", "Alta Via 2 Dolomites"])
  result.layout["legend"] = %*{"orientation": "h", "y": -0.12}
  result.geoAxes((11.55, 12.35), (46.1, 46.8))

proc profile*(pts: DataFrame, trek: string, labels: DataFrame): PlotJson =
  let g = pts.filter(col.trek == trek)
    .groupBy((col.km / 0.1).floor.alias("bin")).agg(col.ele.mean, col.km.mean)
    .sort("bin")
  let line = Trace[float](`type`: PlotType.Scatter, mode: PlotMode.Lines, name: trek,
                          xs: g.toList("km", float), ys: g.toList("ele", float))
  result = finish(@[line], trek & ": elevation profile (100 m bins)", 380)
  result.withStyle(0, %*{"fill": "tozeroy", "line": {"color": "#1f77b4"}})
  for r in labels.rows(tuple[km: float, label: string, ele: float]):
    result.note(r.km, r.ele, r.label, ax = 0, ay = -22, size = 10)
  for a in result.layout["annotations"]: a.delete("bgcolor")
  result.layout["xaxis"] = %*{"title": {"text": "km"}}
  result.layout["yaxis"] = %*{"title": {"text": "m"}, "range": [0, 3000]}

# ---------------------------------------------------------------- the world

proc worldMap*(ranges: DataFrame): PlotJson =
  let r = readParquet("data/relief_world.parquet")
    .select(col.lon, col.lat, (col.ele > 0).cast(Float64).alias("land"))
  let (xs, ys, zs) = grid(r, "land")
  result = finish(@[Trace[float](`type`: PlotType.HeatMap, xs: xs, ys: ys, zs: zs)],
                  "The world's mountain ranges by highest point (GMBA Inventory v2)", 520)
  result.withStyle(0, %*{"colorscale": scale(Land), "showscale": false, "hoverinfo": "skip"})
  let bands = [(0.0, 2000.0, "#f2c48d", "below 2000 m"), (2000.0, 4000.0, "#e08a4c", "2000-4000 m"),
               (4000.0, 6000.0, "#b54b2a", "4000-6000 m"), (6000.0, 9000.0, "#5e1a0e", "above 6000 m")]
  let land = ranges.filter(col.Feature != "Ocean")
  for (lo, hi, color, label) in bands:
    var jx = newJArray()
    var jy = newJArray()
    let band = land.filter(col.Elev_High.isBetween(lo, hi, closed = ClosedInterval.Left))
    for outline in band.toList("outline", seq[seq[seq[float]]]):
      for ring in outline:
        for p in ring:
          jx.add %p[0]; jy.add %p[1]
        jx.add newJNull(); jy.add newJNull()
    result.traces.add %*{"type": "scatter", "mode": "lines", "fill": "toself", "fillcolor": color,
                         "line": {"width": 0.3, "color": color}, "name": label, "x": jx, "y": jy,
                         "hoverinfo": "skip"}
  result.layout["legend"] = %*{"orientation": "h", "y": -0.08}
  result.layout["xaxis"] = %*{"range": [-180, 180], "showgrid": false, "constrain": "domain"}
  result.layout["yaxis"] = %*{"range": [-60, 80], "scaleanchor": "x", "scaleratio": 1,
                              "showgrid": false, "constrain": "domain"}

const Offsets = [("Mount Everest", -40, -30), ("Lhotse", 45, -35), ("Lhotse Shar", 60, 0),
  ("Makalu", 40, 25), ("Cho Oyu", -30, -45), ("Kanchenjunga", 30, 30), ("Shishapangma", 20, -40),
  ("Manaslu", 0, -35), ("Annapurna I", -20, 30), ("Dhaulagiri", -50, -25), ("K2", -10, -40),
  ("Broad Peak", 60, -30), ("Gasherbrum", 70, 0), ("Gasherbrum II", 60, 30), ("Nanga Parbat", -40, 30)]

proc himalayaMap*(high: DataFrame): PlotJson =
  let (bg, bgStyle) = relief("data/relief_himalaya.parquet", 7000)
  let dots = Trace[float](`type`: PlotType.Scatter, mode: PlotMode.Markers, name: "8000ers",
                          xs: high.toList("lon", float), ys: high.toList("lat", float),
                          text: high.toList("peak", string))
  result = finish(@[bg, dots], "The fourteen 8000ers, plus Lhotse Shar", 480)
  result.withStyle(0, bgStyle)
  result.withStyle(1, %*{"marker": {"size": 9, "color": Red, "symbol": "triangle-up",
                                    "line": {"width": 1, "color": "white"}}, "hoverinfo": "text"})
  for r in high.rows(tuple[peak: string, lon, lat: float]):
    var (ax, ay) = (0, -30)
    for (p, x, y) in Offsets:
      if p == r.peak: (ax, ay) = (x, y)
    result.note(r.lon, r.lat, r.peak, ax = ax, ay = ay, size = 10)
  result.layout["showlegend"] = %false
  result.geoAxes((73.0, 89.5), (26.8, 36.6))
