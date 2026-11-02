## Cloud storage against local servers: Python's http.server for https-style
## reads, and moto (a local S3) when `moto_server` is installed.
import std/[unittest, os, osproc, net, httpclient, strutils, options]
import nanuq

proc freePort(): int =
  let s = newSocket()
  s.bindAddr(Port(0), "127.0.0.1")
  result = s.getLocalAddr[1].int
  s.close()

proc waitFor(port: int, p: Process = nil) =
  ## Waits up to 60 s: moto imports a lot on its first start on a CI runner.
  for _ in 0 ..< 600:
    if p != nil and not p.running:
      raise newException(IOError, "server on port " & $port & " exited with code " &
                         $p.peekExitCode)
    try:
      let s = newSocket()
      s.connect("127.0.0.1", Port(port))
      s.close()
      return
    except OSError:
      sleep 100
  raise newException(IOError, "server on port " & $port & " did not start")

# Python's http.server with Range requests, which object stores need.
const rangeServer = """
import http.server, os, sys
class H(http.server.SimpleHTTPRequestHandler):
    def send_head(self):
        r = self.headers.get("Range")
        path = self.translate_path(self.path)
        if not r or not os.path.isfile(path):
            return super().send_head()
        size = os.path.getsize(path)
        a, b = r.split("=")[1].split("-")
        if a == "":
            start, end = max(size - int(b), 0), size - 1
        else:
            start, end = int(a), (int(b) if b else size - 1)
        end = min(end, size - 1)
        f = open(path, "rb")
        f.seek(start)
        self.send_response(206)
        self.send_header("Content-Range", "bytes %d-%d/%d" % (start, end, size))
        self.send_header("Content-Length", str(end - start + 1))
        self.send_header("Accept-Ranges", "bytes")
        self.end_headers()
        self.wfile.write(f.read(end - start + 1))
        f.close()
        return None
    def log_message(self, *a):
        pass
os.chdir(sys.argv[2])
http.server.ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
"""

let df = newDataFrame(series("bear", @["Ada", "Bo"]), series("kg", @[410, 380]))

suite "cloud paths":
  test "isCloudPath":
    check isCloudPath("s3://bucket/x.parquet")
    check isCloudPath("https://example.com/x.csv")
    check isCloudPath("az://c/x.parquet")
    check not isCloudPath("data/x.parquet")
    check not isCloudPath("file:///tmp/x.parquet")

suite "reading over HTTP":
  let dir = getTempDir() / "nanuq_http"
  removeDir(dir)
  createDir(dir)
  df.writeParquet(dir / "bears.parquet")
  df.writeCsv(dir / "bears.csv")
  df.writeIpc(dir / "bears.arrow")
  df.writeNdjson(dir / "bears.ndjson")
  let port = freePort()
  let server = startProcess(findExe("python3"), args = ["-c", rangeServer, $port, dir],
                            options = {poStdErrToStdOut})
  waitFor(port)
  let base = "http://127.0.0.1:" & $port & "/"

  test "readParquet, readCsv, readIpc, readNdjson":
    check readParquet(base & "bears.parquet").toList("kg", int) == @[410, 380]
    check readCsv(base & "bears.csv").toList("bear", string) == @["Ada", "Bo"]
    check readIpc(base & "bears.arrow").height == 2
    check readNdjson(base & "bears.ndjson").toList("kg", int) == @[410, 380]
    check scanParquet(base & "bears.parquet").filter(col.kg > 400).collect.height == 1

  test "a missing file raises":
    expect IOError:
      discard readParquet(base & "nope.parquet")

  server.terminate()
  discard server.waitForExit()
  server.close()

let moto = findExe("moto_server")
if moto.len == 0:
  echo "moto_server not found: skipping the S3 tests"
else:
  suite "S3 (moto)":
    let port = freePort()
    let server = startProcess(moto, args = ["-H", "127.0.0.1", "-p", $port],
                              options = {poParentStreams})
    waitFor(port, server)
    let endpoint = "http://127.0.0.1:" & $port
    let client = newHttpClient()
    discard client.request(endpoint & "/nanuq", httpMethod = HttpPut)
    client.close()
    let opts = {"aws_endpoint_url": endpoint, "aws_access_key_id": "test",
                "aws_secret_access_key": "test", "aws_region": "us-east-1",
                "aws_allow_http": "true"}

    test "write and read back Parquet, CSV, IPC, NDJSON":
      df.writeParquet("s3://nanuq/bears.parquet", storageOptions = opts)
      check readParquet("s3://nanuq/bears.parquet", storageOptions = opts).toList("kg", int) ==
        @[410, 380]
      df.writeCsv("s3://nanuq/bears.csv", storageOptions = opts)
      check readCsv("s3://nanuq/bears.csv", storageOptions = opts).height == 2
      df.writeIpc("s3://nanuq/bears.arrow", storageOptions = opts)
      check readIpc("s3://nanuq/bears.arrow", storageOptions = opts).height == 2
      df.writeNdjson("s3://nanuq/bears.ndjson", storageOptions = opts)
      check readNdjson("s3://nanuq/bears.ndjson", storageOptions = opts).toList("bear", string) ==
        @["Ada", "Bo"]

    test "sinks and partitioned sinks":
      df.lazy.filter(col.kg > 400).sinkParquet("s3://nanuq/big.parquet", storageOptions = opts)
      check scanParquet("s3://nanuq/big.parquet", storageOptions = opts).collect.height == 1
      df.lazy.sinkParquet(PartitionBy(basePath: "s3://nanuq/by_bear", key: @["bear"]),
                          storageOptions = opts)
      check scanParquet("s3://nanuq/by_bear/**/*.parquet", storageOptions = opts).collect.height == 2

    test "a missing bucket raises":
      expect IOError:
        discard readParquet("s3://no-such-bucket/bears.parquet", storageOptions = opts)

    server.terminate()
    discard server.waitForExit()
    server.close()
