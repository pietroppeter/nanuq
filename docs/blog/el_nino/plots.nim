## Plotly figures for "Counting El Niños", with nim-plotly. The twin of figs.py: same
## traces, colours and layout. nim-plotly builds the traces (data, type, mode, name,
## marker) and the basic layout (title, size, axes, colours, legend); what it has no
## field for (hover templates, shapes, styled annotations, colour scales, subplots
## domains, nulls in a heatmap) is added to the JSON it produces.
import std/[json, sequtils, strutils, math, options]
import plotly except Color
import chroma
import nanuq

const
  Surface* = "#fcfcfb"
  Ink = "#1f1f1e"
  Ink2 = "#5c5b57"
  Muted = "#8a8984"
  Grid = "#e6e5e1"
  Blue = "#2a78d6"
  Orange = "#eb6834"
  Aqua = "#1baf7a"
  Warm = "#d1453f"
  Cool = "#2a78d6"
  Grey = "#c9c8c3"
  Land = "#d9d7d0"
  Diverging = [(0.0, "#0d366b"), (0.2, "#256abf"), (0.38, "#86b6ef"), (0.5, "#f0efec"),
               (0.62, "#f2a3a0"), (0.8, "#d1453f"), (1.0, "#7f1d1d")]
  Sequential = [(0.0, "#0d366b"), (0.25, "#3987e5"), (0.45, "#cde2fb"), (0.6, "#fbe3c4"),
                (0.75, "#f0a35e"), (0.9, "#d1453f"), (1.0, "#7f1d1d")]
  Boxes = [("Niño 4", 160.0, 210.0, -5.0, 5.0), ("Niño 3.4", 190.0, 240.0, -5.0, 5.0),
           ("Niño 3", 210.0, 270.0, -5.0, 5.0), ("Niño 1+2", 270.0, 280.0, -10.0, 0.0)]

proc hex(s: string): chroma.Color = parseHex(s[1 .. ^1])

proc scale(stops: openArray[(float, string)]): JsonNode =
  result = newJArray()
  for (p, c) in stops: result.add %*[p, c]

proc layout(title: string, height: int, source = "", legend = false): Layout =
  result = Layout(title: "<b>" & title & "</b>", height: height, autosize: true,
                  backgroundColor: hex(Surface), paperColor: hex(Surface),
                  font: Font(family: "Inter, system-ui, sans-serif", size: 12, color: hex(Ink2)),
                  xaxis: Axis(gridColor: hex(Grid)), yaxis: Axis(gridColor: hex(Grid)))
  if legend:
    result.showlegend = true
    result.legend = Legend(orientation: Orientation.Horizontal, x: 0.0, y: 1.1)

proc finish(p: Plot[float], source = "", hovermode = "closest"): PlotJson =
  ## The JSON nim-plotly makes, plus the common style it has no field for.
  result = p.toPlotJson
  let l = result.layout
  l["title"] = %*{"text": l["title"].getStr, "x": 0.01, "xanchor": "left",
                  "font": {"size": 15, "color": Ink}}
  l["margin"] = %*{"l": 60, "r": 30, "t": 50, "b": (if source.len > 0: 55 else: 40)}
  l["hoverlabel"] = %*{"bgcolor": "white", "font": {"color": Ink}}
  l["hovermode"] = %hovermode
  if not l.hasKey("showlegend"): l["showlegend"] = %false
  for ax in ["xaxis", "yaxis"]:
    if not l.hasKey(ax): l[ax] = newJObject()
    l[ax]["zeroline"] = %false
    l[ax]["linecolor"] = %Grid
    # nim-plotly writes autorange: true when no range is given, which would win over a
    # range set later on the JSON; plotly.js autoranges by default anyway
    l[ax].delete("autorange")
  if source.len > 0:
    if not l.hasKey("annotations"): l["annotations"] = newJArray()
    l["annotations"].add %*{"text": source, "xref": "paper", "yref": "paper", "x": 0,
                            "y": -0.17, "xanchor": "left", "showarrow": false,
                            "font": {"size": 10, "color": Muted}}

proc note(pj: PlotJson, x, y: float, text: string, size = 12, color = Ink2,
          axes = ("x", "y"), extra = newJObject()) =
  if not pj.layout.hasKey("annotations"): pj.layout["annotations"] = newJArray()
  var a = %*{"x": x, "y": y, "text": text, "showarrow": false, "xref": axes[0], "yref": axes[1],
             "font": {"size": size, "color": color}}
  for k, v in extra: a[k] = v
  pj.layout["annotations"].add a

proc shape(pj: PlotJson, s: JsonNode) =
  if not pj.layout.hasKey("shapes"): pj.layout["shapes"] = newJArray()
  pj.layout["shapes"].add s

proc decimalYear(df: DataFrame): seq[float] =
  ## Mid-month as a decimal year, for monthly series on a continuous axis.
  df.select((col.year + (col.month - 0.5) / 12).alias("t")).toList("t", float)

proc line(pj: PlotJson, i: int, color: string, width = 2.0) =
  pj.traces[i]["line"] = %*{"color": color, "width": width}

# ---------------------------------------------------------------- maps

proc lonLabel(t: int): string =
  if t < 180: $t & "°E" elif t == 180: "180°" else: $(360 - t) & "°W"

proc heatmap(field: DataFrame, value: string, xaxis = "x", yaxis = "y"): (Trace[float], JsonNode) =
  ## A heatmap trace of `value` on the lat/lon grid of `field` (one row per grid point).
  ## nim-plotly's `zs` holds no nulls (land), so `z` is returned as JSON.
  let grid = field.pivot(on = "lon", index = "lat", values = value).sort("lat")
  let lons = grid.columns[1 .. ^1].mapIt(parseFloat(it))
  var z = newJArray()
  for r in 0 ..< grid.height:
    var row = newJArray()
    for c in grid.columns[1 .. ^1]:
      let v = grid[c, r, Option[float]]
      row.add(if v.isSome: %v.get else: newJNull())
    z.add row
  (Trace[float](`type`: PlotType.HeatMap, xs: lons, ys: grid.toList("lat", float),
                xaxis: xaxis, yaxis: yaxis), z)

proc mapAxes(pj: PlotJson, n = 1) =
  let ticks = [120, 150, 180, 210, 240, 270]
  for i in 1 .. n:
    let sx = if i == 1: "" else: $i
    pj.layout["xaxis" & sx] = %*{"range": [120, 290], "tickvals": ticks,
                                 "ticktext": ticks.mapIt(lonLabel(it)), "showgrid": false,
                                 "constrain": "domain", "anchor": "y" & sx}
    pj.layout["yaxis" & sx] = %*{"range": [-30, 30], "tickvals": [-30, -15, 0, 15, 30],
                                 "ticktext": ["30°S", "15°S", "0°", "15°N", "30°N"],
                                 "showgrid": false, "anchor": "x" & sx,
                                 "showticklabels": i == 1}
    for ax in ["xaxis" & sx, "yaxis" & sx]:
      pj.layout[ax]["zeroline"] = %false
      pj.layout[ax]["linecolor"] = %Grid
  pj.layout["plot_bgcolor"] = %Land

proc drawBoxes(pj: PlotJson, names: openArray[string], axes = ("x", "y")) =
  for (name, w, e, s, n) in Boxes:
    if name notin names: continue
    pj.shape %*{"type": "rect", "x0": w, "x1": e, "y0": s, "y1": n, "xref": axes[0],
                "yref": axes[1], "line": {"color": Ink, "width": 1.5}}
    pj.note((w + e) / 2, (if name == "Niño 1+2": s - 3 else: n + 2.5), "<b>" & name & "</b>",
            size = 10, color = Ink, axes = axes)

proc pacificNormal*(): PlotJson =
  ## The Pacific in a normal year: 1991-2020 mean SST, with the Niño 3.4 box.
  let (tr, z) = heatmap(readCsv("data/pacific_normal.csv"), "sst")
  let p = Plot[float](traces: @[tr], layout: layout(
    "The Pacific in a normal year: sea surface temperature, 1991-2020 mean", 420))
  result = p.finish(source = "Data: NOAA ERSSTv5. Land in grey.")
  result.traces[0]["z"] = z
  result.traces[0]["colorscale"] = scale(Sequential)
  result.traces[0]["zmin"] = %14; result.traces[0]["zmax"] = %30
  result.traces[0]["colorbar"] = %*{"title": {"text": "°C"}, "len": 0.8, "outlinewidth": 0}
  result.traces[0]["hovertemplate"] = %"%{x}°E, %{y}°<br>%{z:.1f} °C<extra></extra>"
  result.mapAxes
  result.layout["yaxis"]["scaleanchor"] = %"x"
  result.drawBoxes(["Niño 3.4"])
  result.note(145, 4, "<b>warm pool</b>", 13, "white")
  result.note(255, -9, "<b>cold tongue</b>", 13, Ink)
  result.note(205, 11, "", extra = %*{"ax": 258, "ay": 11, "axref": "x", "ayref": "y",
                                      "showarrow": true, "arrowhead": 2, "arrowwidth": 2,
                                      "arrowcolor": Ink})
  result.note(231, 14, "trade winds", color = Ink)

proc anomalyMaps*(months, titles: openArray[string],
                  boxes: openArray[string] = ["Niño 3.4"], title = ""): PlotJson =
  ## Small multiples of SST anomaly maps on one shared diverging scale (±4 °C), in one row.
  let anomaly = readCsv("data/pacific_anomaly.csv")
  let n = months.len
  var p = Plot[float](layout: layout(
    (if title.len > 0: title else: "Sea temperature compared with normal"), 360))
  var zs: seq[JsonNode]
  for i, mo in months:
    let sx = if i == 0: "" else: $(i + 1)
    let (tr, z) = heatmap(anomaly.filter(col.month == mo), "anomaly", "x" & sx, "y" & sx)
    p.traces.add tr; zs.add z
  result = p.finish(source = "Data: NOAA ERSSTv5. Red: warmer than the 1991-2020 normal " &
                             "for that month; blue: cooler.")
  result.mapAxes(n)
  let gap = 0.05
  let w = (1.0 - gap * float(n - 1)) / float(n)
  for i in 0 ..< n:
    let sx = if i == 0: "" else: $(i + 1)
    let t = result.traces[i]
    t["z"] = zs[i]; t["colorscale"] = scale(Diverging)
    t["zmin"] = %(-4); t["zmax"] = %4; t["zmid"] = %0
    t["showscale"] = %(i == 0)
    if i == 0: t["colorbar"] = %*{"title": {"text": "°C"}, "len": 0.7, "tickvals": [-4, -2, 0, 2, 4], "outlinewidth": 0}
    t["hovertemplate"] = %"%{x}°E, %{y}°<br>%{z:+.1f} °C vs normal<extra></extra>"
    let x0 = float(i) * (w + gap)
    result.layout["xaxis" & sx]["domain"] = %*[x0, x0 + w]
    result.note(x0 + w / 2, 1.0, titles[i], 12, Ink, ("paper", "paper"),
                %*{"yanchor": "bottom", "xanchor": "center"})
    result.drawBoxes(boxes, ("x" & sx, "y" & sx))

proc walkerSchematic*(): PlotJson =
  ## Cross-section along the equator, normal conditions vs El Niño, drawn with shapes.
  var p = Plot[float](layout: layout("What changes during El Niño (a slice along the equator)", 360))
  result = p.finish(source = "Schematic, not to scale. After NOAA PMEL's El Niño diagrams.")
  for (sx, title) in [("", "Normal conditions"), ("2", "El Niño")]:
    let nino = sx == "2"
    let (xa, ya) = ("x" & sx, "y" & sx)
    result.layout["xaxis" & sx] = %*{"range": [0, 10], "visible": false,
                                     "domain": (if nino: [0.52, 1.0] else: [0.0, 0.48]), "anchor": ya}
    result.layout["yaxis" & sx] = %*{"range": [-4.8, 4.6], "visible": false, "anchor": xa}
    result.note((if nino: 0.76 else: 0.24), 1.0, title, 14, Ink2, ("paper", "paper"),
                %*{"yanchor": "bottom"})
    let (tw, te) = if nino: (-1.7, -1.4) else: (-2.6, -0.6)  # thermocline depth, west and east
    proc poly(pj: PlotJson, pts: openArray[(float, float)], color: string) =
      pj.shape %*{"type": "path", "xref": xa, "yref": ya, "fillcolor": color, "layer": "below",
                  "line": {"width": 0},
                  "path": "M " & pts.mapIt($it[0] & "," & $it[1]).join(" L ") & " Z"}
    result.poly([(0.6, 0.0), (9.4, 0.0), (9.4, te), (0.6, tw)], "#f2a3a0")    # warm layer
    result.poly([(0.6, tw), (9.4, te), (9.4, -4.0), (0.6, -4.0)], "#9ec5f4")  # cold deep water
    result.poly([(0.0, -4.0), (0.6, -4.0), (0.6, 0.3), (0.0, 0.6)], Land)
    result.poly([(9.4, -4.0), (10.0, -4.0), (10.0, 1.4), (9.4, 0.4)], Land)
    result.shape %*{"type": "line", "xref": xa, "yref": ya, "x0": 0.6, "y0": tw, "x1": 9.4,
                    "y1": te, "line": {"color": Ink2, "dash": "dash", "width": 1}}
    result.note(5, (tw + te) / 2 - 0.5, "thermocline", 10, Ink2, (xa, ya))
    let cx = if nino: 5.8 else: 2.2  # where the air rises and rains
    result.shape %*{"type": "circle", "xref": xa, "yref": ya, "x0": cx - 1.2, "x1": cx + 1.2,
                    "y0": 2.3, "y1": 3.4, "fillcolor": Grey, "line": {"width": 0}}
    for k in 0 .. 4:
      let x = cx - 0.8 + 0.4 * float(k)
      result.shape %*{"type": "line", "xref": xa, "yref": ya, "x0": x, "y0": 2.2,
                      "x1": x - 0.15, "y1": 1.6, "line": {"color": Cool, "width": 1.5}}
    result.note(cx, 3.85, "rain", 11, Ink2, (xa, ya))
    proc arrow(pj: PlotJson, x0, y0, x1, y1: float) =
      pj.note(x1, y1, "", axes = (xa, ya), extra = %*{"ax": x0, "ay": y0, "axref": xa,
              "ayref": ya, "showarrow": true, "arrowhead": 2, "arrowwidth": 1.8, "arrowcolor": Ink})
    if not nino:
      result.arrow(8.6, 0.6, 3.6, 0.6); result.arrow(3.4, 1.0, 3.4, 2.4)
      result.arrow(3.6, 4.2, 8.6, 4.2); result.arrow(8.9, 4.0, 8.9, 1.0)
      result.arrow(8.9, -2.8, 8.9, -0.9)
      result.note(6, 1.0, "strong trade winds", axes = (xa, ya))
      result.note(7.4, 3.0, "dry, sinking air", 10, Ink2, (xa, ya))
      result.note(7.4, -1.9, "cold water wells up", 10, "#0d366b", (xa, ya))
    else:
      result.arrow(3.0, 0.6, 4.4, 0.6); result.arrow(8.6, 0.6, 7.2, 0.6)
      result.note(5.8, -0.6, "warm water spreads east", 10, "#7f1d1d", (xa, ya))
      result.note(1.6, 1.2, "drought", axes = (xa, ya))
      result.note(5.8, 1.0, "weak trade winds", axes = (xa, ya))
    result.note(0.3, -4.5, "Indonesia", 10, Ink2, (xa, ya))
    result.note(9.5, -4.5, "South America", 10, Ink2, (xa, ya))

# ---------------------------------------------------------------- charts

proc oniBars*(oni: DataFrame): PlotJson =
  ## ONI as bars: red at or above +0.5, blue at or below -0.5, grey in between.
  let v = oni.toList("oni", float)
  let colors = v.mapIt(hex(if it >= 0.5: Warm elif it <= -0.5: Cool else: Grey))
  let tr = Trace[float](`type`: PlotType.Bar, xs: oni.decimalYear, ys: v,
                        marker: Marker[float](color: colors))
  let p = Plot[float](traces: @[tr], layout: layout(
    "Oceanic Niño Index 1950-2026: El Niño in red, La Niña in blue", 380))
  result = p.finish(source = "Data: NOAA CPC. Dotted lines at ±0.5 °C.")
  result.traces[0]["marker"]["line"] = %*{"width": 0}
  result.traces[0]["customdata"] = %zip(oni.toList("season", string), oni.toList("year", int)).mapIt(%*[it[0], it[1]])
  result.traces[0]["hovertemplate"] = %"%{customdata[0]} %{customdata[1]}: %{y:+.1f} °C<extra></extra>"
  result.layout["bargap"] = %0
  for y in [0.5, -0.5]:
    result.shape %*{"type": "line", "xref": "paper", "x0": 0, "x1": 1, "y0": y, "y1": y,
                    "line": {"color": Ink2, "width": 1, "dash": "dot"}}
  for (x, y, t) in [(1983.0, 2.4, "1982-83"), (1998.0, 2.65, "1997-98"),
                    (2016.0, 2.85, "2015-16"), (2026.6, 2.45, "2026")]:
    result.note(x, y, t, 11)
  result.layout["yaxis"]["title"] = %*{"text": "ONI, °C"}
  result.layout["yaxis"]["range"] = %*[-2.3, 3.1]
  result.layout["xaxis"]["range"] = %*[1949.5, 2027.5]

proc growth*(side: DataFrame): PlotJson =
  ## Each event's ONI by season since onset; the last column drawn on top, thicker.
  let cols = side.columns[1 .. ^1]
  let palette = [Grey, Blue, Aqua, Orange, Warm]
  var p = Plot[float](layout: layout("2026 is growing faster than any El Niño since 1950",
                                     400, legend = true))
  for i, c in cols:
    p.traces.add Trace[float](`type`: PlotType.Scatter, mode: PlotMode.LinesMarkers,
                              name: (if c == "2014": "2015-16" else: c),
                              xs: side.toList("season_no", float),
                              ys: side.toList(c, Option[float]).mapIt(it.get(NaN)))
  result = p.finish
  for i, c in cols:
    let t = result.traces[i]
    let name = t["name"].getStr
    let ys = side.toList(c, Option[float])
    t["y"] = %ys.mapIt(if it.isSome: %it.get else: newJNull())
    result.line(i, palette[i], if i == cols.high: 3.5 else: 2.0)
    t["marker"] = %*{"size": 7, "color": palette[i]}
    t["mode"] = %"lines+markers+text"
    var text = newSeq[string](ys.len)
    text[ys.filterIt(it.isSome).len - 1] = name
    t["text"] = %text
    t["textposition"] = %"middle right"
    t["hovertemplate"] = %(name & ", season %{x}: %{y:.1f} °C<extra></extra>")
  result.layout["xaxis"]["title"] = %*{"text": "season since the event began"}
  result.layout["xaxis"]["range"] = %*[0.7, 9.0]
  result.layout["xaxis"]["dtick"] = %1
  result.layout["yaxis"]["title"] = %*{"text": "ONI, °C"}

proc twoRulers*(oni, roni: DataFrame, since = 1995): PlotJson =
  var p = Plot[float](layout: layout("Two rulers for the same ocean", 360, legend = true))
  let series = [(oni, Grey, "ONI (official until January 2026)"),
                (roni, Warm, "RONI (official since February 2026)")]
  for (df, color, name) in series:
    let d = df.filter(col.year >= since)
    p.traces.add Trace[float](`type`: PlotType.Scatter, mode: PlotMode.Lines, name: name,
                              xs: d.decimalYear, ys: d.toList("oni", float))
  result = p.finish(hovermode = "x unified")
  for i, (df, color, name) in series:
    let d = df.filter(col.year >= since)
    result.line(i, color)
    result.traces[i]["customdata"] = %zip(d.toList("season", string), d.toList("year", int)).mapIt(%*[it[0], it[1]])
    result.traces[i]["hovertemplate"] = %(name.split(" ")[0] &
      " %{customdata[0]} %{customdata[1]}: %{y:+.1f}<extra></extra>")
  result.shape %*{"type": "line", "xref": "paper", "x0": 0, "x1": 1, "y0": 0.5, "y1": 0.5,
                  "line": {"color": Ink2, "width": 1, "dash": "dot"}}
  result.layout["yaxis"]["title"] = %*{"text": "°C"}
  result.layout["xaxis"]["range"] = %*[since, 2027]

proc soiVsOni*(both: DataFrame, since = 1980): PlotJson =
  ## Two stacked panels, one per measure (never a second y-axis).
  let d = both.filter(col.year >= since)
  let t = d.decimalYear
  var p = Plot[float](layout: layout("Ocean and atmosphere move together", 440))
  for (c, warmIfPos, ya) in [("mine", true, "y"), ("soi3", false, "y2")]:
    let v = d.toList(c, float)
    p.traces.add Trace[float](`type`: PlotType.Bar, xs: t, ys: v, yaxis: ya,
      marker: Marker[float](color: v.mapIt(hex(if (it >= 0) == warmIfPos: Warm else: Cool))))
  result = p.finish(source = "Data: NOAA CPC. Red marks the El Niño side of each index.")
  for tr in result.traces:
    tr["marker"]["line"] = %*{"width": 0}
    tr["hovertemplate"] = %"%{x:.1f}: %{y:+.2f}<extra></extra>"
  result.layout["bargap"] = %0
  result.layout["xaxis"]["range"] = %*[since, 2027]
  result.layout["xaxis"]["anchor"] = %"y2"
  result.layout["yaxis"]["domain"] = %*[0.56, 1.0]
  result.layout["yaxis2"] = %*{"domain": [0.0, 0.44], "anchor": "x", "gridcolor": Grid,
                               "zeroline": false}
  result.note(0, 1.0, "Sea: Niño 3.4 anomaly, °C (3-month mean)", 12, Ink, ("paper", "paper"),
              %*{"xanchor": "left", "yanchor": "bottom"})
  result.note(0, 0.44, "Air: Southern Oscillation Index (3-month mean), its mirror image", 12,
              Ink, ("paper", "paper"), %*{"xanchor": "left", "yanchor": "bottom"})

proc boxLines*(boxes: DataFrame, since = 2014): PlotJson =
  let d = boxes.filter(col.year >= since)
  var p = Plot[float](layout: layout("Three of the four boxes, 2014-2026", 380, legend = true))
  let series = [("nino12_anom", Orange, "Niño 1+2 (coast of Peru)"),
                ("nino34_anom", Warm, "Niño 3.4 (central Pacific)"),
                ("nino4_anom", Blue, "Niño 4 (west)")]
  for (c, color, name) in series:
    p.traces.add Trace[float](`type`: PlotType.Scatter, mode: PlotMode.Lines, name: name,
                              xs: d.decimalYear, ys: d.toList(c, float))
  result = p.finish(source = "Data: NOAA CPC (OISST v2.1).", hovermode = "x unified")
  for i, (c, color, name) in series:
    result.line(i, color)
    result.traces[i]["hovertemplate"] = %(name.split(" (")[0] & ": %{y:+.2f} °C<extra></extra>")
  result.note(2017.2, 2.9, "2017: coast only", 11)
  result.note(2023.2, 2.9, "2023: coast first", 11)
  result.layout["yaxis"]["title"] = %*{"text": "°C vs normal"}
  result.layout["xaxis"]["range"] = %*[since, 2027]

proc piura*(years: DataFrame): PlotJson =
  let d = years.withColumns(col.date.dt.year.alias("y"))
  let full = d.toList("days", int).mapIt(it >= 300)
  let tr = Trace[float](`type`: PlotType.Bar, xs: d.toList("y", float),
                        ys: d.toList("rain_mm", float),
                        marker: Marker[float](color: full.mapIt(hex(if it: Blue else: "#b7d3f6"))))
  let p = Plot[float](traces: @[tr], layout: layout("Piura, Peru: rain in a desert city", 360))
  result = p.finish(source = "Data: NOAA GHCN-Daily, Piura airport. Light bars: fewer than " &
                             "300 days reported that year.")
  result.traces[0]["customdata"] = %d.toList("days", int)
  result.traces[0]["hovertemplate"] = %"%{x}: %{y:,.0f} mm (%{customdata} days reported)<extra></extra>"
  for yr in [1983, 1998, 2017]:
    let v = d.filter(col.y == yr)["rain_mm"].item(float)
    result.note(float(yr), v, $yr, extra = %*{"yshift": 12})
  result.layout["yaxis"]["title"] = %*{"text": "rain per year, mm"}

proc world*(yearly, smooth, records: DataFrame): PlotJson =
  let s = smooth.withColumns(col.date.dt.year.alias("year"), col.date.dt.month.alias("month"))
  var p = Plot[float](layout: layout("The world's temperature, 1880-2026", 400, legend = true))
  p.traces.add Trace[float](`type`: PlotType.Scatter, mode: PlotMode.Lines,
                            name: "monthly, smoothed (ewmMean, span 12)",
                            xs: s.decimalYear, ys: s.toList("ewm12", float))
  p.traces.add Trace[float](`type`: PlotType.Scatter, mode: PlotMode.Lines, name: "yearly mean",
                            xs: yearly.toList("year", float).mapIt(it + 0.5),
                            ys: yearly.toList("temp", float))
  p.traces.add Trace[float](`type`: PlotType.Scatter, mode: PlotMode.Markers, name: "record year",
                            xs: records.toList("year", float).mapIt(it + 0.5),
                            ys: records.toList("temp", float))
  result = p.finish(source = "Data: NASA GISS, GISTEMP v4.")
  result.line(0, "#9ec5f4", 1.2); result.line(1, Blue)
  result.traces[2]["marker"] = %*{"color": Warm, "size": 8, "line": {"color": Surface, "width": 2}}
  result.traces[0]["hovertemplate"] = %"%{y:.2f} °C<extra></extra>"
  result.traces[1]["hovertemplate"] = %"%{x:.0f}: %{y:.2f} °C<extra></extra>"
  result.traces[2]["hovertemplate"] = %"record %{x:.0f}: %{y:.2f} °C<extra></extra>"
  result.layout["yaxis"]["title"] = %*{"text": "°C vs 1951-1980"}
  result.layout["xaxis"]["range"] = %*[1880, 2027]

proc recent*(table: DataFrame): PlotJson =
  var p = Plot[float](layout: layout("Month by month, 2023-2026", 380, legend = true))
  let series = [("2023", Aqua), ("2024", Blue), ("2025", Grey), ("2026", Warm)]
  for (c, color) in series:
    p.traces.add Trace[float](`type`: PlotType.Scatter, mode: PlotMode.LinesMarkers, name: c,
                              xs: table.toList("mon", float),
                              ys: table.toList(c, Option[float]).mapIt(it.get(NaN)))
  result = p.finish(hovermode = "x unified")
  for i, (c, color) in series:
    result.traces[i]["y"] = %table.toList(c, Option[float]).mapIt(
      if it.isSome: %it.get else: newJNull())
    result.line(i, color, if c == "2026": 3.5 else: 2.0)
    result.traces[i]["marker"] = %*{"size": 6, "color": color}
    result.traces[i]["hovertemplate"] = %(c & ": %{y:.2f} °C<extra></extra>")
  result.layout["xaxis"]["tickvals"] = %toSeq(1 .. 12)
  result.layout["xaxis"]["ticktext"] = %"JFMAMJJASOND".mapIt($it)
  result.layout["yaxis"]["title"] = %*{"text": "°C vs 1951-1980"}
