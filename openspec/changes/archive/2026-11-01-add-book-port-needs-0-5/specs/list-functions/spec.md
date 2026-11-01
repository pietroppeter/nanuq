## ADDED Requirements

### Requirement: Exploding several columns by name
DataFrame and LazyFrame `explode` SHALL also take several column names as separate
arguments: `explode("a", "b")` is `explode(["a", "b"])`.

```nim
let df = newDataFrame:
  peak: ["Mont Blanc", "Monte Rosa"]
  huts: [@["Goûter", "Cosmiques"], @["Margherita", "Gnifetti"]]
  m: [@[3835, 3613], @[4554, 3647]]
echo df.explode("huts", "m")
```

```text
```

#### Scenario: Lists of equal length
- **WHEN** two list columns with lists of the same lengths are exploded together
- **THEN** each row holds the matching elements of both
