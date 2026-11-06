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
| PFMKANCATT | Inside BEDIT on PFSUITE_ANCHOR: adds whichever of the anchor's nine tags (V5's eight + CL) the block lacks, invisible. PFSETUP won't write an anchor until they're all there |
| PFSEL | Inside BEDIT: selects a nested profile symbol by its state name |
| PFGATE | Pick a placed CBI or pipe: checks its tags, parameters and states. Dry-runs PFTOP, PFDEPTH, a label move and every size's width. Ends "ready to test" or not |
| PFRECTEST | Pick a **test** insert: round-trips pf-record |
| PFSYNCTEST | Run 1 snapshots every suite block (read only). You ATTSYNC. Run 2 reports what was lost |
| PFPIPETEST | Places a pipe by code and checks it followed |
| PFGRIDTEST | Lists the anchors, reads the grid you click, prints station and elevation at your clicks, and shows where the .cl came from |
| PFLINETEST | What the line tree sees, read only: every line (grid or V5 stub, `.cl` read or walked), every structure on it in station order with its built name, a `*` where PFNAME differs, then near misses, structures on no line, stacked pairs, and the anchor checks for every grid. Lay it beside V5's labels on the same drawing |
| PFSELFTEST | The test sheet, run by code (Jake, 2026-10-30: "I want PFSELFTEST to do all of the testing"). No picks: it makes its own test blocks far out in model space, drives the real suite code against them, prints PASS / FAIL with what it got, then erases them. Real blocks are only read. Groups: 1 label rows (per-type prefixes, PFELEVPRE), 2 pipe label inside/outside, 3 PFREFRESH scope, 4 line tree, 5 grid anchors (PFSETUP's writer and checks, PFREMOVE), then on **test lines of its own** (STORM_YA / YB / YC, `.cl` files written to `%TEMP%\PFSELFTEST`, a grid each): 6 PFSETUP Scan / Anchor / Edit, 7 PFASSIGN (and Assign for one line), 8 PFSTRUCT, 9 PFREFRESH, 10 PFPIPE and the leader, 11 what PFREMOVE leaves, 12 the palette's trees, panels and refusals. Groups 6-11 call each command's work function (`pfn:scan-in`, `pfn:place-rec`, `pfn:edit-check` / `edit-write`, `pfa:run`, `pfs:run`, `pfu:run`, `pfp:place`) with their own answers, and read what it says through `pfb:hush` (pf-lib's `*pfl-quiet*`) instead of printing it. **Every new module ships with its group** (Jake, 2026-10-30). Left by hand: the dialog, the clicks, UNDO, save / reopen, another drawing, ATTSYNC. (Core Console can't do this: its ActiveX is off, so no dynamic block is recognised -- tried 2026-10-27.) |

## Rules

- **No copies of shared code.** It calls pf-lib, pf-record, pf-draw and the rest. Only its own reporting helpers live here.
- **Never paste multi-line test sequences at the command line.** Wrap them in a bench command instead.
