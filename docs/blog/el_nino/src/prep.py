"""Turn the raw NOAA/NASA downloads (raw/) into the small CSVs the post reads (data/).
Run from the draft folder: python3 -I src/prep.py raw data"""
import csv, gzip, sys, os
raw, out = sys.argv[1:3]
def write(name, header, rows):
    with open(os.path.join(out, name), "w", newline="") as f:
        w = csv.writer(f); w.writerow(header); w.writerows(rows)
    print(name, len(rows))

# Niño 3.4 monthly SST (ERSSTv6) with CPC's sliding 30-year climatology
rows = [l.split() for l in open(f"{raw}/detrend.nino34.ascii.txt") if l.strip()][1:]
write("nino34.csv", ["year", "month", "sst", "cpc_normal", "cpc_anomaly"], rows)

# the four Niño boxes, monthly OISST v2.1 since 1982
rows = [l.split() for l in open(f"{raw}/sstoi.indices") if l.strip()][1:]
write("nino_boxes.csv", ["year", "month", "nino12", "nino12_anom", "nino3", "nino3_anom",
                         "nino4", "nino4_anom", "nino34", "nino34_anom"], rows)

# Southern Oscillation Index, standardized section, fixed width: year(4) + 12 x 6 chars
lines = open(f"{raw}/soi").read().split("\n")
start = [i for i, l in enumerate(lines) if "STANDARDIZED" in l][0] + 3
rows = []
for l in lines[start:]:
    if not l[:4].isdigit(): break
    for m in range(12):
        v = l[4 + 6 * m: 10 + 6 * m].strip()
        rows.append([l[:4], m + 1, "" if v == "-999.9" else v])
while rows and rows[-1][2] == "": rows.pop()
write("soi.csv", ["year", "month", "soi"], rows)

# Piura (Peru) daily rain from GHCN-Daily, tenths of mm -> mm, drop values with a quality flag
rows = []
for r in csv.reader(gzip.open(f"{raw}/PEM00084401.csv.gz", "rt")):
    if r[2] == "PRCP" and r[5] == "":
        d = r[1]; rows.append([f"{d[:4]}-{d[4:6]}-{d[6:]}", int(r[3]) / 10])
write("piura_rain.csv", ["date", "rain_mm"], rows)
