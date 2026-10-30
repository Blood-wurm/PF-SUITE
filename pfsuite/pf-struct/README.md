# pf-struct.lsp — PFSTRUCT: place the structures

**Load position:** 10 (after pf-assign).
**May depend on:** pf-cfg, pf-lib, pf-carlson, pf-record, pf-anchor, pf-index, pf-draw.
**Depended on by:** pf-pipe (`pfs:ctx`, for the invert step later).

## What it owns

**PFSTRUCT: "place structures in profile"** (Jake, 2026-10-16). One command
for every structure type; it was called PFDRAW. **No grid pick:** it covers
every line in the drawing. Once the palette exists, it will take the line
clicked there.
1. pushes the drafter inputs (STA prefix etc.) to every structure;
2. grid by grid, **every alpha block on the line with no profile copy yet** gets one, on the grid that shows its station;
3. writes the new copy's label rows, puts them at the grid top, and fits the station line to the **first** row.

**Copies already placed are left alone.** From then on, PFREFRESH carries
them: updates (an alpha block re-stationed by PFASSIGN included), and
clearing orphans and duplicates.

## Label standard (Jake, 2026-10-16)

```
STA. 4+09.69 STORM LINE 'BA' =      grid's own line first, then others A-Z
STA. 3+00.00 STORM LINE 'BC'        " =" on all but the last station row
CONST. DRAINAGE MH BA-5/BC-1        prefix + type words + PFNAME, no size
W/ CURB INLET CASTING
G.L. 758.25
```

- **The wording is a default.** Drafters type over any row that should differ, and it's kept.
- **The suffix comes from the .cl name:** `[util] LINE '[line]'`, split at the first underscore.
- **No grid top at a station:** say so, and put the labels `*pf-top-default*` text heights above the structure.

## Rules

- **A label row moved by hand is left where it is.** A row reset by ATTSYNC, sitting at its block position, is put back.
- **Each copy gets a fingerprint** (`pfs:copy-fp`), which PFREFRESH compares to see if anything changed.
- **Structures only.** It never reads or changes pipes, and never writes inverts.
- **The tool never touches PFDEPTH.**
- **The plan record is the truth,** so rerunning is always safe.
