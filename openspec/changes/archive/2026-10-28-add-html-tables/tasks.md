# Tasks

## 1. Bridge

- [x] 1.1 Add a Rust function formatting one cell (by column and row, with a string length limit) like py-polars' `get_fmt`, returning the needed length when the buffer is too small; mirror it in `ffi.nim`; verify `cargo build --release` passes

## 2. toHtml

- [x] 2.1 Add `toHtml(df, maxRows = 10, maxCols = 75)` to `src/nanuq.nim`, ported from py-polars' `HTMLFormatter` / `NotebookFormatter`; verify with tests for truncation, escaping, nulls and a wide frame
- [x] 2.2 Compare with Python: render penguins and a small mixed-dtype frame in Python Polars (if available in the container) and check the HTML is identical; otherwise compare against stored expected output; record the Polars version used

## 3. Dev log

- [x] 3.1 Add `table.dataframe` CSS to `docs/nanuqtheme.nim` (light and dark)
- [x] 3.2 Add one short section to "How Nanuq works" showing a result as text and as `nbRawHtml: summary.toHtml`; leave every other output as text; verify the post renders and republish its artifact
- [x] 3.3 Check CI is green on the PR

## Workflow follow-up

- Archive the change: remove "nimib integration" from BACKLOG.md and add a CHANGELOG line.
