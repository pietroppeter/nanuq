## Plotly figures for "Move 37", with nim-plotly. The twin of src/figs.py: same traces,
## colours and layout (without Plotly's "plotly_white" template, which only Python
## ships). nim-plotly builds the traces (type, data, mode, name, marker, text) and the
## basic layout (title, size); what it has no field for (board lines as shapes, colour
## scales as stops, several heatmaps side by side, axis ranges and aspect ratio) is
## added to the JSON it produces.
import std/[json, sequtils]
import plotly except Color
import nanuq

const
  Kaya = "#dcb468"
  Ink = "#3b2f1e"
  Stars = [3, 9, 15]
  Cols = "ABCDEFGHJKLMNOPQRST"  # go boards skip the letter I

proc finish(traces: seq[Trace[float]], title: string, height: int): PlotJson =
  ## The JSON nim-plotly makes, with the white template figs.py uses.
  let p = Plot[float](traces: traces, layout: Layout(title: title, height: height, autosize: true))
  result = p.toPlotJson
  let l = result.layout
  l["title"] = %*{"text": l["title"].getStr, "x": 0.05}
  l["plot_bgcolor"] = %"white"
  l["margin"] = %*{"l": 30, "r": 20, "t": 50, "b": 30}
  for ax in ["xaxis", "yaxis"]:
    if not l.hasKey(ax): l[ax] = newJObject()
    if l[ax].hasKey("autorange"): l[ax].delete("autorange")

proc floats(df: DataFrame, column: string): seq[float] =
  df.select(col(column).cast(Float64)).toList(column, float)

proc withStyle(pj: PlotJson, i: int, style: JsonNode) =
  for k, v in style: pj.traces[i][k] = v

proc gridShapes(size: int, xref = "x", yref = "y"): seq[JsonNode] =
  ## The wooden board, then its lines (x = column 0..18 left to right, y = row 0..18 top down).
  result.add %*{"type": "rect", "x0": -0.8, "x1": size.float - 0.2, "y0": -0.8, "y1": size.float - 0.2,
                "xref": xref, "yref": yref, "fillcolor": Kaya, "line": {"width": 0}, "layer": "below"}
  for i in 0 ..< size:
    result.add %*{"type": "line", "x0": 0, "x1": size - 1, "y0": i, "y1": i, "xref": xref, "yref": yref,
                  "line": {"color": Ink, "width": 1}, "layer": "below"}
    result.add %*{"type": "line", "x0": i, "x1": i, "y0": 0, "y1": size - 1, "xref": xref, "yref": yref,
                  "line": {"color": Ink, "width": 1}, "layer": "below"}

proc board*(stones: DataFrame, title: string, labels = DataFrame(), size = 19, height = 560): PlotJson =
  ## stones: x, y, color ("B"/"W"); labels: optional x, y, text, fg.
  var stars: seq[(float, float)]
  for x in Stars:
    for y in Stars: stars.add (x.float, y.float)
  var traces = @[Trace[float](`type`: PlotType.Scatter, mode: PlotMode.Markers,
                              xs: stars.mapIt(it[0]), ys: stars.mapIt(it[1]))]
  for c in ["B", "W"]:
    let s = stones.filter(col.color == c)
    traces.add Trace[float](`type`: PlotType.Scatter, mode: PlotMode.Markers,
                            name: (if c == "B": "black" else: "white"),
                            xs: s.floats("x"), ys: s.floats("y"))
  result = finish(traces, title, height)
  result.withStyle(0, %*{"marker": {"size": 6, "color": Ink}, "hoverinfo": "skip", "showlegend": false})
  let stoneSize = height.float / (size + 2).float * 0.9
  result.withStyle(1, %*{"marker": {"size": stoneSize, "color": "#111111", "line": {"width": 1, "color": "#000000"}},
                         "hoverinfo": "skip", "showlegend": false})
  result.withStyle(2, %*{"marker": {"size": stoneSize, "color": "#f8f8f4", "line": {"width": 1, "color": "#555555"}},
                         "hoverinfo": "skip", "showlegend": false})
  if labels.width > 0:
    result.traces.add %*{"type": "scatter", "mode": "text", "x": labels.floats("x"), "y": labels.floats("y"),
                         "text": labels.toList("text", string),
                         "textfont": {"color": labels.toList("fg", string), "size": 11},
                         "hoverinfo": "skip", "showlegend": false}
  result.layout["width"] = %(height - 20)
  result.layout["shapes"] = %gridShapes(size)
  result.layout["xaxis"] = %*{"range": [-1, size], "showgrid": false, "zeroline": false,
    "tickvals": toSeq(0 ..< size), "ticktext": toSeq(Cols[0 ..< size]).mapIt($it), "side": "top",
    "constrain": "domain"}
  result.layout["yaxis"] = %*{"range": [size, -1], "showgrid": false, "zeroline": false,
    "tickvals": toSeq(0 ..< size), "ticktext": toSeq(0 ..< size).mapIt($(size - it)),
    "scaleanchor": "x", "constrain": "domain"}

proc heatBoards*(freq: DataFrame, panels: openArray[string], title: string, height = 330): PlotJson =
  ## freq: panel, x, y, share; one 19x19 heatmap per panel, side by side.
  let zmax = freq.select(col.share.max).toList("share", float)[0]
  var traces: seq[Trace[float]]
  for p in panels:
    let f = freq.filter(col.panel == p)
    var z = newSeqWith(19, newSeq[float](19))
    for r in f.select(col.x, col.y, col.share).rows(tuple[x, y: int, share: float]):
      z[r.y][r.x] = r.share
    traces.add Trace[float](`type`: PlotType.HeatMap, xs: toSeq(0 .. 18).mapIt(it.float),
                            ys: toSeq(0 .. 18).mapIt(it.float), zs: z)
  result = finish(traces, title, height)
  let n = panels.len
  let gap = 0.03
  let w = (1.0 - gap * float(n - 1)) / float(n)
  var notes = newJArray()
  for i, p in panels:
    let suffix = if i == 0: "" else: $(i + 1)
    result.withStyle(i, %*{"zmin": 0, "zmax": zmax,
      "colorscale": [[0, "#f3e3bd"], [0.25, "#e0a84f"], [0.6, "#b4462b"], [1, "#3a0f12"]],
      "showscale": i == n - 1, "hovertemplate": "%{z:.1%}<extra></extra>",
      "colorbar": {"tickformat": ".0%", "len": 0.8}, "xaxis": "x" & suffix, "yaxis": "y" & suffix})
    let x0 = float(i) * (w + gap)
    result.layout["xaxis" & suffix] = %*{"domain": [x0, x0 + w], "anchor": "y" & suffix,
      "range": [-0.5, 18.5], "showticklabels": false, "showgrid": false, "zeroline": false, "constrain": "domain"}
    result.layout["yaxis" & suffix] = %*{"domain": [0, 1], "anchor": "x" & suffix,
      "range": [18.5, -0.5], "showticklabels": false, "showgrid": false, "zeroline": false,
      "constrain": "domain", "scaleanchor": "x" & suffix}
    notes.add %*{"text": p, "x": x0 + w / 2, "y": 1.0, "xref": "paper", "yref": "paper",
                 "xanchor": "center", "yanchor": "bottom", "showarrow": false, "font": {"size": 16}}
  result.layout["annotations"] = notes
  result.layout["plot_bgcolor"] = %"#f3e3bd"

proc linesAt[T](df: DataFrame, x: string, ys: openArray[(string, string, string)], title, ytitle: string,
                events: openArray[(T, string)], yformat: string, height: int, mode: string): PlotJson =
  ## One line per (column, name, colour); dotted vertical lines with a label for events.
  result = finish(@[], title, height)
  let xs = if df.schema[x] == Date: %df.select(col(x).cast(String)).toList(x, string) else: %df.floats(x)
  for (y, name, color) in ys:
    var jy = newJArray()
    for v in df.select(col(y).cast(Float64)).toList(y, Option[float]):
      jy.add(if v.isSome: %v.get else: newJNull())
    result.traces.add %*{"type": "scatter", "mode": mode, "name": name, "x": xs, "y": jy,
                         "line": {"color": color}}
  var shapes = newJArray()
  var notes = newJArray()
  for (ex, text) in events:
    shapes.add %*{"type": "line", "x0": ex, "x1": ex, "y0": 0, "y1": 1, "yref": "paper",
                  "line": {"color": "#999", "dash": "dot"}}
    notes.add %*{"x": ex, "y": 1, "yref": "paper", "text": text, "showarrow": false,
                 "yanchor": "bottom", "font": {"size": 11, "color": "#555"}}
  if shapes.len > 0:
    result.layout["shapes"] = shapes
    result.layout["annotations"] = notes
  result.layout["yaxis"] = %*{"title": {"text": ytitle}, "automargin": true}
  if yformat.len > 0: result.layout["yaxis"]["tickformat"] = %yformat
  result.layout["legend"] = %*{"orientation": "h", "y": -0.15}

proc bars*(df: DataFrame, x, y: string, title, ytitle: string, color = "#8c5a2b",
           height = 400, yformat = ""): PlotJson =
  result = finish(@[Trace[float](`type`: PlotType.Bar, xs: @[], ys: df.floats(y))], title, height)
  result.traces[0]["x"] = %df.toList(x, string)
  result.withStyle(0, %*{"marker": {"color": color}})
  result.layout["yaxis"] = %*{"title": {"text": ytitle}, "automargin": true}
  if yformat.len > 0: result.layout["yaxis"]["tickformat"] = %yformat


proc lines*[T](df: DataFrame, x: string, ys: openArray[(string, string, string)], title, ytitle: string,
               events: openArray[(T, string)], yformat = "", height = 420,
               mode = "lines+markers"): PlotJson =
  linesAt(df, x, ys, title, ytitle, events, yformat, height, mode)

proc lines*(df: DataFrame, x: string, ys: openArray[(string, string, string)], title, ytitle: string,
            yformat = "", height = 420, mode = "lines+markers"): PlotJson =
  ## Lines without event markers.
  linesAt(df, x, ys, title, ytitle, newSeq[(int, string)](), yformat, height, mode)
