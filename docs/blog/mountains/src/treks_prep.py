"""Flatten waymarkedtrails route details into one NDJSON line per trek.

Keeps the nesting the explainer wants to show: trek -> stages -> ways -> points,
with OSM tags kept as raw dicts (heterogeneous keys) and points as [x, y, ele]
in Web Mercator metres (EPSG:3857), elevation sampled from AWS terrarium tiles.
"""
import io, json, math, sys, time, pathlib, urllib.request
from PIL import Image

RAW = pathlib.Path(sys.argv[1])          # raw/wmt
OUT = pathlib.Path(sys.argv[2])          # data/treks.ndjson
TILES = pathlib.Path(sys.argv[3])        # tile cache dir
Z = 13
HALF = 20037508.342789244
_tiles = {}

def tile(x, y):
    key = (x, y)
    if key not in _tiles:
        p = TILES / f"{Z}_{x}_{y}.png"
        if not p.exists():
            url = f"https://elevation-tiles-prod.s3.amazonaws.com/terrarium/{Z}/{x}/{y}.png"
            for i in range(4):
                try:
                    p.write_bytes(urllib.request.urlopen(url, timeout=60).read()); break
                except Exception:
                    time.sleep(2 ** i)
        _tiles[key] = Image.open(p).convert("RGB").load()
    return _tiles[key]

def ele(mx, my):
    n = 2 ** Z
    fx = (mx + HALF) / (2 * HALF) * n
    fy = (HALF - my) / (2 * HALF) * n
    tx, ty = int(fx), int(fy)
    px, py = min(int((fx - tx) * 256), 255), min(int((fy - ty) * 256), 255)
    r, g, b = tile(tx, ty)[px, py]
    return round(r * 256 + g + b / 256 - 32768, 1)

def main_ways(node, stage, out):
    rt = node.get("route_type")
    if rt == "base":
        out.append((stage, node)); return
    if rt == "route" and "id" in node:
        stage = node["id"]
    for c in node.get("main", []):
        main_ways(c, stage, out)
    for c in node.get("ways", []):
        main_ways(c, stage, out)

TREKS = [9678362, 1176308, 10353523, 49181, 177743, 404914, 1706143, 3020521]
with OUT.open("w") as f:
    for tid in TREKS:
        d = json.loads((RAW / f"{tid}.details.json").read_text())
        subs = d.get("subroutes") or {}
        ways = []
        main_ways(d["route"], tid, ways)
        stages, order = {}, []
        for sid, w in ways:
            if sid not in stages:
                s = subs.get(str(sid), {})
                stages[sid] = {"id": sid, "name": s.get("name", d["name"]),
                               "itinerary": s.get("itinerary", d.get("itinerary", [])), "ways": []}
                order.append(sid)
            pts = [[round(x, 1), round(y, 1), ele(x, y)] for x, y in w["geometry"]["coordinates"]]
            stages[sid]["ways"].append({"id": w["id"], "length": w["length"], "direction": w["direction"],
                                        "tags": w.get("tags", {}), "points": pts})
        rec = {"id": tid, "name": d["name"], "ref": d.get("ref"), "tags": d["tags"],
               "official_length": d.get("official_length"), "stages": [stages[s] for s in order]}
        f.write(json.dumps(rec, ensure_ascii=False) + "\n")
        print(tid, d["name"], len(order), "stages", len(ways), "ways", file=sys.stderr)
