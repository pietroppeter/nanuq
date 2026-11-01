"""Coordinates for the 82 UIAA 4000ers -> data/uiaa_coords.csv (nr, lon, lat, source).

1. Wikidata P625 of the en.wikipedia article linked from the list (raw/uiaa_coords.csv)
2. else a Camptocamp summit (raw/c2c/alps4000_*.json, Web Mercator) picked by hand below
3. else a Wikidata item in the Alps >= 4000 m with the same label (data/wd_alps4000.csv)
Subsummits that share an article (Breithorn, Lyskamm, Vincent Pyramid) use Camptocamp."""
import csv, glob, json, math, re, sys, unicodedata, urllib.parse
R = 6378137.0
def norm(s):
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode().lower()
    return re.sub(r"[^a-z]", "", re.sub(r"\[.*?\]|\(.*?\)", "", s))
C2C = {3: "Pointe Dufour", 5: "Pointe Zumstein", 6: "Pointe Gnifetti", 8: "Lyskamm / Liskamm E",
       11: "Lyskamm / Liskamm W", 15: "Pointe Parrot", 29: "Hobärghorn / Hohberghorn",
       30: "Pyramide Vincent", 39: "Breithorn W", 41: "Breithorn Central", 43: "Breithorn E",
       51: "Breithorn - Pointe 4106", 63: "Grand Paradis", 67: "Pointe Giordani",
       69: "Gross Grünhorn", 72: "Dirruhorn / Dürrenhorn", 79: "Pointe Baretti"}
c2c = {}
for f in glob.glob("raw/c2c/alps4000_*.json"):
    for d in json.load(open(f))["documents"]:
        x, y = json.loads(d["geometry"]["geom"])["coordinates"]
        c2c[d["locales"][0]["title"]] = (x / R * 180 / math.pi, math.degrees(math.atan(math.sinh(y / R))))
pt = lambda s: tuple(float(v) for v in s[6:-1].split())
art = {urllib.parse.unquote(r["article"].split("/wiki/")[1]): pt(r["coord"]) for r in csv.DictReader(open("raw/uiaa_coords.csv")) if r["coord"]}
wd = {}
for r in csv.DictReader(open("data/wd_alps4000.csv")):
    if r["coord"]: wd.setdefault(norm(r["mLabel"]), pt(r["coord"]))
out = csv.writer(open("data/uiaa_coords.csv", "w")); out.writerow(["nr", "lon", "lat", "source"])
for nr, name, link in json.load(open("raw/uiaa_links.json")):
    if nr in C2C: lon, lat = c2c[C2C[nr]]; src = "camptocamp"
    elif link in art: (lon, lat), src = art[link], "wikidata"
    else: (lon, lat), src = wd[norm(name)], "wikidata-label"
    out.writerow([nr, round(lon, 5), round(lat, 5), src])
