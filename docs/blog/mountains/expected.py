"""Runs mountains.py cell by cell and writes each code cell's output to expected/<id>.txt.

As in a notebook, a cell's last bare expression is printed. Figure cells (fig_*) save the
Plotly JSON instead. These files are what the Nim post must reproduce.
Run from this folder: python3 -I expected.py"""
import ast, contextlib, io, os, re
os.chdir(os.path.dirname(os.path.abspath(__file__)))
os.makedirs("expected", exist_ok=True)
src = open("mountains.py").read()
ns = {}
def run(code, name):
    tree = ast.parse(code)
    last = tree.body.pop() if tree.body and isinstance(tree.body[-1], ast.Expr) else None
    exec(compile(tree, name, "exec"), ns)
    if last is not None:
        v = eval(compile(ast.Expression(last.value), name, "eval"), ns)
        if v is not None: print(v)
for cell in src.split("\n# %%")[1:]:
    if cell.startswith(" [markdown]"): continue
    cid = re.match(r"\n# id: (\S+)", cell).group(1)
    if cid.startswith("fig_"):
        ns["figs"].SAVE_PATH = f"expected/{cid}.json"
        run(cell, cid); ns["figs"].SAVE_PATH = None
        print(cid, "figure"); continue
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        run(cell, cid)
    open(f"expected/{cid}.txt", "w").write(buf.getvalue().rstrip("\n") + "\n")
    print(cid, len(buf.getvalue().splitlines()), "lines")
