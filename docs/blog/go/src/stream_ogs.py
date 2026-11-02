import sys, zlib, urllib.request, time
URL = "https://za3k.com/ogs/ogs_games_2013_to_2025-05.json.gz"
out = open(sys.argv[1], "wb"); every = int(sys.argv[2])
d = zlib.decompressobj(16 + zlib.MAX_WBITS)
pos = 0; n = 0; buf = b""; fails = 0
while True:
    try:
        req = urllib.request.Request(URL, headers={"Range": f"bytes={pos}-"})
        with urllib.request.urlopen(req, timeout=60) as r:
            while True:
                chunk = r.read(1 << 20)
                if not chunk: break
                pos += len(chunk)
                buf += d.decompress(chunk)
                lines = buf.split(b"\n"); buf = lines.pop()
                for l in lines:
                    if n % every == every - 1: out.write(l + b"\n")
                    n += 1
        if d.eof or pos >= 45847026468: break
    except Exception as e:
        fails += 1; print("retry", pos, n, e, flush=True); time.sleep(min(30, 2 ** min(fails, 5)))
print("done", pos, n, flush=True)
