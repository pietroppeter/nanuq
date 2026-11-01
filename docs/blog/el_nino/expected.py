"""Runs el_nino.py cell by cell and writes each code cell's stdout to expected/<id>.txt.

Those files are the outputs the Nim post shows, and later its acceptance test.
Run from this folder: python3 -I expected.py"""
import contextlib, io, os, re
os.chdir(os.path.dirname(os.path.abspath(__file__)))
os.makedirs("expected", exist_ok=True)
src = open("el_nino.py").read()
ns = {}
for cell in src.split("\n# %%")[1:]:
    if cell.startswith(" [markdown]"): continue
    m = re.match(r"\n# id: (\S+)", cell)
    if m.group(1).startswith("fig_"):  # figures: keep the Plotly JSON, no text output
        ns["figs"].SAVE_PATH = f"expected/{m.group(1)}.json"
        exec(compile(cell, m.group(1), "exec"), ns)
        ns["figs"].SAVE_PATH = None
        continue
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        exec(compile(cell, m.group(1), "exec"), ns)
    open(f"expected/{m.group(1)}.txt", "w").write(buf.getvalue().rstrip("\n") + "\n")
    print(m.group(1), len(buf.getvalue().splitlines()), "lines")
