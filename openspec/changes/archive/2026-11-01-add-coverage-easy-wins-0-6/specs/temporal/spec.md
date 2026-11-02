# Spec Delta

## ADDED Requirements

### Requirement: More date parts and time ranges
`dt.epoch(EpochUnit)` SHALL give the time since 1970-01-01 (whole seconds and days for
`Seconds` and `Days`), `dt.century` and `dt.millennium` the century and millennium,
`dt.dstOffset` and `dt.baseUtcOffset` the offsets of zoned datetimes as Durations.
`timeRange(start, stop, interval, closed)` SHALL give times of day, `timeRanges` one
list per row.

```nim
let df = newDataFrame(series("d", @[date(2000, 6, 1), date(2001, 1, 1)]))
echo df.select(col("d").dt.epoch(EpochUnit.Days).alias("days"),
               col("d").dt.century.alias("century"))
echo select(timeRange(timeOfDay(9), timeOfDay(11), "1h").alias("t"))
```

```text
TBD
```

#### Scenario: Daylight saving
- **WHEN** `dt.dstOffset` runs on 2026-07-01 12:00 in Europe/Rome
- **THEN** the result is 1 hour

### Requirement: Business days
`dt.addBusinessDays(n, weekMask, holidays, roll)`, `dt.isBusinessDay(weekMask, holidays)`
and `businessDayCount(start, stop, weekMask, holidays)` SHALL count business days:
Monday to Friday by default (`weekMask`, Monday first), minus `holidays`. `roll` SHALL say
what a start date that is not a business day does (`Raise`, `Forward`, `Backward`).

```nim
let df = newDataFrame(series("d", @[date(2026, 10, 30)]))
echo df.select(col("d").dt.addBusinessDays(1).alias("next"),
               col("d").dt.isBusinessDay.alias("business"))
echo select(businessDayCount(date(2026, 11, 2), date(2026, 11, 9)).alias("n")).toList("n", int)
```

```text
TBD
```

#### Scenario: Holiday
- **WHEN** one business day is added to Friday 2026-10-30 with Monday 2026-11-02 a holiday
- **THEN** the result is 2026-11-03
