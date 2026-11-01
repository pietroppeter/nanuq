"""GMBA Mountain Inventory v2.0 (standard, 300 selection) -> data/gmba_ranges.ndjson.

Keeps the attribute strings as published (Path "A > B > C", Countries "X, Y") and adds the
outline simplified to ~0.05 degrees as a list of polygons, each a list of [lon, lat] rings
(outer ring only). Source: https://www.earthenv.org/mountains (Snethlage et al. 2022)."""
import json, sys, shapefile
from shapely.geometry import shape
d = sys.argv[1]  # folder with the unzipped shapefile
base = f"{d}/GMBA_Inventory_v2.0_standard_300"
r = shapefile.Reader(shp=open(base + ".shp", "rb"), dbf=open(base + ".dbf", "rb"), shx=open(base + ".shx", "rb"))
keep = ["GMBA_V2_ID", "MapName", "WikiDataUR", "Hier_Lvl", "Feature", "Area", "Elev_Low", "Elev_High", "Path", "Countries", "CountryISO"]
with open("data/gmba_ranges.ndjson", "w") as f:
    for sr in r.iterShapeRecords():
        rec = sr.record.as_dict()
        g = shape(sr.shape.__geo_interface__).simplify(0.05, preserve_topology=True)
        polys = [g] if g.geom_type == "Polygon" else list(g.geoms)
        rings = [[[round(x, 3), round(y, 3)] for x, y in p.exterior.coords] for p in polys if p.area > 0.01]
        out = {k: rec[k] for k in keep}
        out["outline"] = rings
        f.write(json.dumps(out, ensure_ascii=False) + "\n")
