# pf-bench.lsp — the workbench (NOT part of the suite)

**Load position:** last.
**May depend on:** anything above it.
**Depended on by:** nothing. **No suite module may call into it.**

## What it owns

Everything that exists to build or check the suite, rather than run it, in
one file. V5 grew thirteen diagnostic commands; this stays one file. It is
deleted whole when V6 ships.

| Command | What it does |
|---|---|
| PFMKATT | Inside BEDIT: builds the attribute definitions from `*pf-tags*`, so no tag is mistyped |
| PFMKPIPEATT | Inside BEDIT on PFSUITE_PIPE: adds PFLABEL2 (row 2, a copy of PFLABEL one row below) and the label inputs PFLENPRE, PFLENSUF, PFSLOPEPRE, PFSLOPESUF |
| PFSEL | Inside BEDIT: selects a nested profile symbol by its state name |
| PFGATE | Pick a placed CBI or pipe: checks its tags, parameters and states. Dry-runs PFTOP, PFDEPTH, a label move and every size's width. Ends "ready to test" or not |
| PFRECTEST | Pick a **test** insert: round-trips pf-record |
| PFSYNCTEST | Run 1 snapshots every suite block (read only). You ATTSYNC. Run 2 reports what was lost |
| PFPIPETEST | Places a pipe by code and checks it followed |
| PFGRIDTEST | Lists the anchors, reads the grid you click, prints station and elevation at your clicks, and shows where the .cl came from |
| PFLINETEST | What the line tree sees, read only: every line (grid or V5 stub, `.cl` read or walked), every structure on it in station order with its built name, a `*` where PFNAME differs, then near misses and structures on no line. Lay it beside V5's labels on the same drawing |
| PFSELFTEST | The test sheet's checks, run by code. No picks: it makes two test CBIs far out in model space and a pipe in the first grid, drives the real suite code against them, prints PASS / FAIL with what it got, then erases them. Real blocks are only read. Groups: label rows (per-type prefixes, PFELEVPRE), pipe label inside/outside, PFREFRESH scope, line tree. **Add a group with every new feature.** (Core Console can't do this: its ActiveX is off, so no dynamic block is recognised -- tried 2026-10-27.) |

## Rules

- **No copies of shared code.** It calls pf-lib, pf-record, pf-draw and the rest. Only its own reporting helpers live here.
- **Never paste multi-line test sequences at the command line.** Wrap them in a bench command instead.
