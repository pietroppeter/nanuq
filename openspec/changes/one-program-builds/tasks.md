## 1. Implementation

- [x] 1.1 `tests/all.nim`: every test file in one program, optional packages detected
- [x] 1.2 `tests/specsuite.nim` + `tests/test_specs*.nim`: spec examples as unittest tests
- [x] 1.3 `tools/specexamples.nim`: one program for all specs (own program for specs importing other packages)
- [x] 1.4 `docs/all.nim`: the whole site in one program; `useDevlogPost` resets the display config
- [x] 1.5 `config.nims`: lld without debug info when available
- [x] 1.6 CI and nimble tasks use the runners; cache `~/.nimble` and moto
- [ ] 1.7 Measure CI before/after with warm caches
