# Proposal

## Why

specview shows OpenSpec changes, but not the specs they produce: to read what the API
promises today, Pietro has to open each `openspec/specs/*/spec.md` on GitHub. And with
every change archived, the page is dominated by finished work. Pietro asked on
2026-11-01 for the full specs in the viewer and for archived changes to be hidden by
default.

## What Changes

- specview renders every main spec in full (purpose, requirements with their examples
  and scenarios), one collapsible block per capability, with an index. Specs touched by
  an open change, or changed since `--base`, are marked.
- Archived changes are hidden by default, in the overview and in the page, behind a
  "Show archived changes" checkbox (remembered in the browser). Archived changes that
  changed since `--base` stay visible, so a PR that archives changes still shows them.
  A link to a hidden change reveals it.
- A small navigation bar links to Changes, Specs and (with `--base`) the file diff.

## Capabilities

### New Capabilities
- `spec-review`: what the specview page shows.

## Differences from Polars

None: this is repository tooling, with no API surface.

## Impact

- `tools/specview.nim` only (still standard library only).
