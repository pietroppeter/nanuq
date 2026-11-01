import std/[unittest, options]
import nanuq

type
  Phase = enum Neutral, ElNino, LaNina
  Reading = object
    station: string
    rain: float
    year: int
  Event = object
    start: Date
    phase: Phase
    peak: Option[float]

suite "rows as objects":
  let df = newDataFrame(series("station", ["Lima", "Piura"]), series("rain", [1.5, 80.0]),
                        series("year", [1998, 1998]), series("extra", [true, false]))
  test "objects":
    check df.rows(Reading) == @[Reading(station: "Lima", rain: 1.5, year: 1998),
                                Reading(station: "Piura", rain: 80.0, year: 1998)]
  test "named tuples, iterator, single row":
    var names: seq[string]
    for r in df.iterRows(tuple[station: string, rain: float]): names.add r.station
    check names == @["Lima", "Piura"]
    check df.row(-1, Reading).station == "Piura"
    expect IndexDefect: discard df.row(5, Reading)
  test "missing column":
    expect ColumnNotFoundError:
      discard df.rows(tuple[station: string, wind: float])
  test "nulls need Option":
    let g = newDataFrame(series("station", ["a"]), series("rain", [none(float)]),
                         series("year", [1]))
    expect InvalidOperationError: discard g.rows(Reading)

suite "objects to a frame":
  test "round trip with options, enums and dates":
    let events = @[Event(start: date(1997, 5, 1), phase: ElNino, peak: some(2.4)),
                   Event(start: date(1998, 7, 1), phase: LaNina, peak: none(float))]
    let df = events.toDataFrame
    check df.columns == @["start", "phase", "peak"]
    check df.toList("peak", Option[float]) == @[some(2.4), none(float)]
    check df.rows(Event) == events
