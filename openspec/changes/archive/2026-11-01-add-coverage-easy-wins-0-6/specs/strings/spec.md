# Spec Delta

## ADDED Requirements

### Requirement: Escaping and normalizing
`str.escapeRegex` SHALL escape regex metacharacters, and `str.normalize(form =
UnicodeForm.NFC)` SHALL give the Unicode normal form (`NFC`, `NFKC`, `NFD`, `NFKD`).

```nim
let df = newDataFrame(series("s", @["a.b*c", "é"]))
echo df.select(col("s").str.escapeRegex.alias("escaped"),
               col("s").str.normalize.str.lenChars.alias("chars"))
```

```text
TBD
```

#### Scenario: Composed form
- **WHEN** "e" followed by a combining acute accent is normalized to NFC
- **THEN** the result is the one character "é"
