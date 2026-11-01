"""Runs aged19.py cell by cell and writes each code cell's stdout to expected/<id>.txt.

docs/blog/aged_19.nim compares each of its blocks with these files, and rendering the
post fails when an output differs.
Run from this folder: python3 -I expected.py"""
import contextlib, io, os, re
os.chdir(os.path.dirname(os.path.abspath(__file__)))
os.makedirs("expected", exist_ok=True)
src = open("aged19.py").read()
ns = {}
for cell in src.split("\n# %%")[1:]:
    if cell.startswith(" [markdown]"): continue
    m = re.match(r"\n# id: (\S+)", cell)
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        exec(compile(cell, m.group(1), "exec"), ns)
    open(f"expected/{m.group(1)}.txt", "w").write(buf.getvalue().rstrip("\n") + "\n")
    print(m.group(1), len(buf.getvalue().splitlines()), "lines")
