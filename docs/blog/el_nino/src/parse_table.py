"""Parse CPC's ONI or RONI HTML table into a wide CSV (year x 12 seasons) and a colour CSV."""
import re, sys, csv
src, out, colours = sys.argv[1:4]
t = open(src, errors="replace").read()
seas = "DJF JFM FMA MAM AMJ MJJ JJA JAS ASO SON OND NDJ".split()
vals, cols = [], []
for r in re.findall(r"<tr[^>]*>(.*?)</tr>", t, flags=re.S):
    cells = re.findall(r"<t[dh][^>]*>(.*?)</t[dh]>", r, flags=re.S)
    txt = [re.sub(r"<[^>]+>|&nbsp;", "", c).strip() for c in cells]
    if not txt or not re.fullmatch(r"\d{4}", txt[0]) or len(cells) > 13: continue
    col = ["warm" if re.search(r"color:red|roni-warm", c) else "cold" if re.search(r"color:blue|roni-cold", c) else "" for c in cells[1:]]
    pad = 13 - len(cells)
    vals.append([txt[0]] + txt[1:] + [""] * pad); cols.append([txt[0]] + col + [""] * pad)
for path, data in [(out, vals), (colours, cols)]:
    with open(path, "w", newline="") as f:
        w = csv.writer(f); w.writerow(["year"] + seas); w.writerows(data)
print(len(vals), vals[0], vals[-1], cols[-1])
