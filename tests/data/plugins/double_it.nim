## A minimal Polars expression plugin, for tests/test_plugins.nim: `double_it`
## doubles a Float64 column (nulls stay null). It implements the plugin C ABI
## (polars-ffi version 0.1) by hand, with nothing but the Arrow C structs.
## Build: nim c --app:lib -d:useMalloc --threads:on double_it.nim

type
  ArrowSchema {.bycopy.} = object
    format, name, metadata: cstring
    flags, nChildren: int64
    children, dictionary: pointer
    release: proc (s: ptr ArrowSchema) {.cdecl.}
    privateData: pointer
  ArrowArray {.bycopy.} = object
    length, nullCount, offset, nBuffers, nChildren: int64
    buffers: ptr UncheckedArray[pointer]
    children, dictionary: pointer
    release: proc (a: ptr ArrowArray) {.cdecl.}
    privateData: pointer
  SeriesExport {.bycopy.} = object
    field: ptr ArrowSchema
    arrays: ptr UncheckedArray[ptr ArrowArray]
    len: csize_t
    release: proc (e: ptr SeriesExport) {.cdecl.}
    privateData: pointer
  Out = object            # everything one exported series owns
    schema: ArrowSchema
    arr: ptr ArrowArray
    arrs: array[1, ptr ArrowArray]

proc c_malloc(n: csize_t): pointer {.importc: "malloc", header: "<stdlib.h>".}
proc c_calloc(n, s: csize_t): pointer {.importc: "calloc", header: "<stdlib.h>".}
proc c_free(p: pointer) {.importc: "free", header: "<stdlib.h>".}

var lastError {.threadvar.}: cstring

proc getVersion(): uint32 {.exportc: "_polars_plugin_get_version", dynlib, cdecl.} = 1
proc getLastError(): cstring {.exportc: "_polars_plugin_get_last_error_message", dynlib, cdecl.} =
  if lastError.isNil: "" else: lastError

proc c_strdup(s: cstring): cstring {.importc: "strdup", header: "<string.h>".}

proc releaseSchema(s: ptr ArrowSchema) {.cdecl.} =
  c_free(s.privateData); s.release = nil
proc releaseArray(a: ptr ArrowArray) {.cdecl.} =
  # Polars releases the array after the series export is gone: the buffer list
  # is the array's own (privateData), not part of `Out`.
  c_free(a.buffers[0]); c_free(a.buffers[1]); c_free(a.privateData); a.release = nil
proc releaseOut(e: ptr SeriesExport) {.cdecl.} =
  let o = cast[ptr Out](e.privateData)
  o.schema.release(o.schema.addr); c_free(o.arr); c_free(o); e.release = nil

proc float64Field(name: cstring): ArrowSchema =
  # A copy of the name (the input's goes away with the input). Polars reads a nil
  # privateData as "no result", so it holds the copy.
  let own = c_strdup(name)
  ArrowSchema(format: "g", name: own, flags: 2, release: releaseSchema, privateData: own)

proc field(fields: ptr UncheckedArray[ArrowSchema], n: csize_t, ret: ptr ArrowSchema,
           kw: pointer, kwLen: csize_t) {.exportc: "_polars_plugin_field_double_it", dynlib, cdecl.} =
  ret[] = float64Field(fields[0].name)

proc doubleIt(inputs: ptr UncheckedArray[SeriesExport], n: csize_t, kw: pointer, kwLen: csize_t,
              ret: ptr SeriesExport, ctx: pointer) {.exportc: "_polars_plugin_double_it", dynlib, cdecl.} =
  let input = inputs[0].addr
  if n != 1 or input.field.format != "g":
    lastError = "double_it takes one Float64 column"
  else:
    var total = 0
    for c in 0 ..< input.len.int: total += input.arrays[c].length.int
    let values = cast[ptr UncheckedArray[float64]](c_malloc(csize_t(8 * max(total, 1))))
    let valid = cast[ptr UncheckedArray[uint8]](c_calloc(csize_t(total div 8 + 1), 1))
    var at, nulls = 0
    for c in 0 ..< input.len.int:
      let a = input.arrays[c]
      let vb = cast[ptr UncheckedArray[uint8]](a.buffers[0])
      let xs = cast[ptr UncheckedArray[float64]](a.buffers[1])
      for i in 0 ..< a.length.int:
        let j = a.offset.int + i
        if vb.isNil or ((vb[j shr 3] shr (j and 7)) and 1) == 1:
          values[at] = 2 * xs[j]
          valid[at shr 3] = valid[at shr 3] or uint8(1 shl (at and 7))
        else: inc nulls
        inc at
    let o = cast[ptr Out](c_calloc(csize_t(sizeof(Out)), 1))
    o.schema = float64Field(input.field.name)
    let bufs = cast[ptr UncheckedArray[pointer]](c_malloc(csize_t(2 * sizeof(pointer))))
    bufs[0] = valid; bufs[1] = values
    o.arr = cast[ptr ArrowArray](c_calloc(csize_t(sizeof(ArrowArray)), 1))
    o.arr[] = ArrowArray(length: total, nullCount: nulls, nBuffers: 2, buffers: bufs,
                         release: releaseArray, privateData: bufs)
    o.arrs[0] = o.arr
    ret[] = SeriesExport(field: o.schema.addr, arrays: cast[ptr UncheckedArray[ptr ArrowArray]](o.arrs.addr),
                         len: 1, release: releaseOut, privateData: o)
  # the plugin owns its inputs: release every chunk, then the export
  for c in 0 ..< input.len.int: input.arrays[c].release(input.arrays[c])
  input.release(input)
