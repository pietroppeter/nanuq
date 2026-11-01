"""Elevation grids for the map backgrounds, sampled from AWS terrarium tiles (Mapzen/Tilezen
terrain, https://registry.opendata.aws/terrain-tiles/).
data/relief_alps.parquet : lon 5.5..12.5, lat 44..47.6, step 0.025 deg (zoom 9)
data/relief_world.parquet: lon -180..179, lat -60..80, step 1 deg (zoom 4)
data/relief_west.parquet, relief_dolomites.parquet (zoom 11) and relief_himalaya.parquet (zoom 7): close-ups"""
import math, pathlib, time, urllib.request
from PIL import Image
CACHE = pathlib.Path("tiles"); CACHE.mkdir(exist_ok=True)
_t = {}
def tile(z, x, y):
    if (z, x, y) not in _t:
        p = CACHE / f"{z}_{x}_{y}.png"
        if not p.exists():
            url = f"https://elevation-tiles-prod.s3.amazonaws.com/terrarium/{z}/{x}/{y}.png"
            for i in range(4):
                try: p.write_bytes(urllib.request.urlopen(url, timeout=60).read()); break
                except Exception: time.sleep(2 ** i)
        _t[(z, x, y)] = Image.open(p).convert("RGB").load()
    return _t[(z, x, y)]
def ele(z, lon, lat):
    n = 2 ** z
    fx = (lon + 180) / 360 * n
    fy = (1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2 * n
    tx, ty = int(fx) % n, min(int(fy), n - 1)
    r, g, b = tile(z, tx, ty)[min(int((fx - int(fx)) * 256), 255), min(int((fy - int(fy)) * 256), 255)]
    return round(r * 256 + g + b / 256 - 32768)
def grid(path, z, lons, lats):
    import polars as pl
    rows = [(round(lon, 3), round(lat, 3), ele(z, lon, lat)) for lat in lats for lon in lons]
    pl.DataFrame(rows, schema={"lon": pl.Float64, "lat": pl.Float64, "ele": pl.Int16},
                 orient="row").write_parquet(path, compression="zstd", compression_level=19)
grid("data/relief_alps.parquet", 9, [5.5 + i * 0.025 for i in range(281)], [44 + i * 0.025 for i in range(145)])
grid("data/relief_world.parquet", 4, [-180 + i for i in range(360)], [-60 + i for i in range(141)])
grid("data/relief_west.parquet", 11, [6.6 + i * 0.006 for i in range(301)], [45.55 + i * 0.004 for i in range(201)])
grid("data/relief_dolomites.parquet", 11, [11.55 + i * 0.004 for i in range(201)], [46.1 + i * 0.003 for i in range(234)])
grid("data/relief_himalaya.parquet", 7, [70 + i * 0.05 for i in range(501)], [26 + i * 0.05 for i in range(221)])
