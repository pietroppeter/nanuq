"""Cut the Pacific out of NOAA ERSSTv5 (raw/grid/ersst5.nc) for the post's maps.
Writes data/pacific_sst.nc: the 1991-2020 monthly normals and the months the post maps.
Run from the draft folder: python3 -I src/maps_prep.py raw/grid/ersst5.nc data/pacific_sst.nc"""
import sys, xarray as xr
src, out = sys.argv[1:3]
sst = xr.open_dataset(src)["sst"].sel(lat=slice(40, -40), lon=slice(100, 300))
normal = sst.sel(time=slice("1991-01-01", "2020-12-01")).groupby("time.month").mean("time")
months = ["1988-12-01", "1997-09-01", "1997-12-01", "2015-09-01", "2015-12-01",
          "2017-03-01", "2023-12-01", "2026-07-01", "2026-08-01", "2026-09-01"]
picked = sst.sel(time=months)
anom = picked.groupby("time.month") - normal
xr.Dataset({"normal": normal, "sst": picked, "anomaly": anom.drop_vars("month")}).to_netcdf(out)
print(xr.open_dataset(out))

# The same fields as long CSV tables (one row per grid point), which both posts read
# with their DataFrame library: data/pacific_normal.csv and data/pacific_anomaly.csv.
ds = xr.open_dataset(out).sel(lat=slice(30, -30), lon=slice(120, 290))
normal_df = ds.normal.mean("month").to_dataframe(name="sst").reset_index()
normal_df.round(2).to_csv("data/pacific_normal.csv", index=False)
anom_df = ds.anomaly.to_dataframe(name="anomaly").reset_index()
anom_df["month"] = anom_df["time"].dt.strftime("%Y-%m")
anom_df[["month", "lat", "lon", "anomaly"]].round(2).to_csv("data/pacific_anomaly.csv", index=False)
print(len(normal_df), len(anom_df))
