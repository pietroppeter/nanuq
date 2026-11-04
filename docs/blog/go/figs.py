"""Plotly figures for the go explainer. Only scatter, heatmap and bar traces plus layout
shapes/annotations, so that nim-plotly can redraw every one of them.
Set SAVE_PATH to write the figure JSON instead of showing it (used by expected.py)."""
import plotly.graph_objects as go
import plotly.io as pio
from plotly.subplots import make_subplots
pio.renderers.default = "notebook"

SAVE_PATH = None
KAYA = "#dcb468"
STARS = [3, 9, 15]
COLS = "ABCDEFGHJKLMNOPQRST"  # go boards skip the letter I

def _out(fig):
    fig.update_layout(template="plotly_white", margin=dict(l=30, r=20, t=50, b=30))
    if SAVE_PATH:
        open(SAVE_PATH, "w").write(fig.to_json())
    else:
        fig.show()

def _grid(fig, size=19, row=None, col=None, xref="x", yref="y"):
    """Board lines and star points; x = column 0..18 left to right, y = row 0..18 top down."""
    fig.add_shape(type="rect", x0=-0.8, x1=size - 0.2, y0=-0.8, y1=size - 0.2, xref=xref, yref=yref,
                  fillcolor=KAYA, line=dict(width=0), layer="below")
    for i in range(size):
        fig.add_shape(type="line", x0=0, x1=size - 1, y0=i, y1=i, xref=xref, yref=yref,
                      line=dict(color="#3b2f1e", width=1), layer="below")
        fig.add_shape(type="line", x0=i, x1=i, y0=0, y1=size - 1, xref=xref, yref=yref,
                      line=dict(color="#3b2f1e", width=1), layer="below")
    stars = [(x, y) for x in STARS for y in STARS] if size == 19 else []
    return go.Scatter(x=[p[0] for p in stars], y=[p[1] for p in stars], mode="markers",
                      marker=dict(size=6, color="#3b2f1e"), hoverinfo="skip", showlegend=False)

def _axes(fig, size=19, **kw):
    fig.update_xaxes(range=[-1, size], showgrid=False, zeroline=False, tickvals=list(range(size)),
                     ticktext=list(COLS[:size]), side="top", constrain="domain", **kw)
    fig.update_yaxes(range=[size, -1], showgrid=False, zeroline=False, tickvals=list(range(size)),
                     ticktext=[str(size - i) for i in range(size)], scaleanchor="x" if not kw else None,
                     constrain="domain", **kw)

def board(stones, title, labels=None, size=19, height=560):
    """stones: frame with x, y, color ("B"/"W"); labels: optional frame x, y, text."""
    fig = go.Figure()
    fig.add_trace(_grid(fig, size))
    for c, fill, line in [("B", "#111111", "#000000"), ("W", "#f8f8f4", "#555555")]:
        s = stones.filter(stones["color"] == c)
        fig.add_trace(go.Scatter(x=s["x"], y=s["y"], mode="markers", name="black" if c == "B" else "white",
                                 marker=dict(size=height / (size + 2) * 0.9, color=fill, line=dict(width=1, color=line)),
                                 hoverinfo="skip", showlegend=False))
    if labels is not None:
        fig.add_trace(go.Scatter(x=labels["x"], y=labels["y"], text=labels["text"], mode="text",
                                 textfont=dict(color=labels["fg"].to_list(), size=11), hoverinfo="skip", showlegend=False))
    fig.update_layout(title=title, height=height, width=height - 20, plot_bgcolor="white")
    _axes(fig, size)
    _out(fig)

def heat_boards(freq, panels, title, height=330):
    """freq: frame with panel, x, y, share; one 19x19 heatmap per panel, side by side."""
    fig = make_subplots(rows=1, cols=len(panels), subplot_titles=panels, horizontal_spacing=0.03)
    zmax = freq["share"].max()
    for i, p in enumerate(panels):
        f = freq.filter(freq["panel"] == p)
        z = [[0.0] * 19 for _ in range(19)]
        for x, y, s in zip(f["x"], f["y"], f["share"]):
            z[y][x] = s
        fig.add_trace(go.Heatmap(z=z, x=list(range(19)), y=list(range(19)), zmin=0, zmax=zmax,
                                 colorscale=[[0, "#f3e3bd"], [0.25, "#e0a84f"], [0.6, "#b4462b"], [1, "#3a0f12"]],
                                 showscale=(i == len(panels) - 1), hovertemplate="%{z:.1%}<extra></extra>",
                                 colorbar=dict(tickformat=".0%", len=0.8)), row=1, col=i + 1)
        fig.update_xaxes(range=[-0.5, 18.5], showticklabels=False, showgrid=False, zeroline=False,
                         constrain="domain", row=1, col=i + 1)
        fig.update_yaxes(range=[18.5, -0.5], showticklabels=False, showgrid=False, zeroline=False,
                         constrain="domain", scaleanchor=f"x{i + 1 if i else ''}", row=1, col=i + 1)
    fig.update_layout(title=title, height=height, plot_bgcolor="#f3e3bd")
    _out(fig)

def lines(df, x, ys, title, ytitle, events=(), yformat=None, height=420, mode="lines+markers"):
    fig = go.Figure()
    for y, name, color in ys:
        fig.add_trace(go.Scatter(x=df[x], y=df[y], name=name, mode=mode, line=dict(color=color)))
    for ex, text in events:
        fig.add_shape(type="line", x0=ex, x1=ex, y0=0, y1=1, yref="paper", line=dict(color="#999", dash="dot"))
        fig.add_annotation(x=ex, y=1, yref="paper", text=text, showarrow=False, yanchor="bottom",
                           font=dict(size=11, color="#555"))
    fig.update_layout(title=title, height=height, yaxis_title=ytitle, legend=dict(orientation="h", y=-0.15))
    if yformat:
        fig.update_yaxes(tickformat=yformat)
    _out(fig)

def bars(df, x, y, title, ytitle, color="#8c5a2b", text=None, height=400, yformat=None):
    fig = go.Figure(go.Bar(x=df[x], y=df[y], marker_color=color,
                           text=df[text] if text else None, textposition="outside"))
    fig.update_layout(title=title, height=height, yaxis_title=ytitle)
    if yformat:
        fig.update_yaxes(tickformat=yformat)
    _out(fig)
