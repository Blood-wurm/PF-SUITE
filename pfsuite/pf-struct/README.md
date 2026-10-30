# pf-struct.lsp — PFSTRUCT: place the structures

**Load position:** 10 (after pf-assign).
**May depend on:** pf-cfg, pf-lib, pf-carlson, pf-record, pf-anchor, pf-index, pf-draw.
**Depended on by:** pf-pipe (`pfs:ctx`, for the invert step later).

## What it owns

**PFSTRUCT: "place structures in profile"** (Jake, 2026-10-16). One command
for every structure type; it was called PFDRAW. **No grid pick:** it covers
every line in the drawing. Once the palette exists, it will take the line
clicked there.
1. pushes the drafter inputs (STA prefix etc.) to every structure **of the same block type**;
2. grid by grid, **every alpha block on the line with no profile copy yet** gets one, on the grid that shows its station;
3. writes the new copy's label rows, puts them at the grid top, and fits the station line to the **first** row.

**Copies already placed are left alone.** From then on, PFREFRESH carries
them: updates (an alpha block re-stationed by PFASSIGN included), and
clearing orphans and duplicates.

**The command is split** (2026-10-30): `pfs:main` reads the drawing and
shares the inputs; `pfs:run plans grids top fmt` places and returns
`(placed already-placed skipped)`. `pfs:sync-fmt-in ents` shares the inputs
over the blocks given (`pfs:sync-fmt` = every structure). PFSELFTEST group 8
calls both with its own test blocks.

## Label standard (Jake, 2026-10-16)

```
STA. 4+09.69 STORM LINE 'BA' =      PFSTAPRE + station + PFSTASUF; grid's own line first, then others A-Z
STA. 3+00.00 STORM LINE 'BC'        " =" on all but the last station row
CONST. CURB BOX INLET BA-5/BC-1     PFCONPRE + PFNAME + PFCONSUF, no size
                                    PFTEXT2: the drafter's, blank unless typed
G.L. 758.25                         PFELEVPRE + rim + PFELEVSUF
```

- **Built from the attributes only** (Jake, 2026-10-27): no wording from a table. The type's wording is PFCONPRE's default.
- **The inputs are shared per block type.** Type one on any CBI and the next run pushes it to every CBI; a DBI keeps its own.
- **Defaults per type** (`*pf-type-fmt*` in pf-cfg):

  | Type | PFCONPRE | PFELEVPRE |
  |---|---|---|
  | CBI, CBI-BOX | `CONST. CURB BOX INLET` | `G.L.` |
  | DBI | `CONST. DROP BOX INLET` | `T.G.` |
  | SMH | `CONST. SANITARY MH` | `T.R.` |
  | DMH | `CONST. DRAINAGE MH` | `T.R.` |
  | MH | `CONST. MANHOLE` | `T.R.` |
  | HDWL | `CONST. HDWL` | blank |

  The rest: PFSTAPRE `STA.`, PFSTASUF `[util] LINE '[line]'`, PFCONSUF and PFELEVSUF blank.
- **A blank PFELEVPRE draws no elevation row.**
- **A block without PFELEVPRE yet** uses its type's default, and the run says so: BEDIT it, PFMKATT, then ATTSYNC.
- **`CONST.` is a retired default.** A structure still holding the `CONST.` the tool wrote, never retyped, gets its type's new default. Anything typed is kept.
- **Any row can be typed over,** and it's kept.
- **The suffix comes from the .cl name:** `[util] LINE '[line]'`, split at the first underscore.
- **No grid top at a station:** say so, and put the labels `*pf-top-default*` text heights above the structure.

## Rules

- **A label row moved by hand is left where it is.** A row reset by ATTSYNC, sitting at its block position, is put back. Refitting PFTOP rebuilds the insert and can carry a moved row with it, so its spot is noted first and it is put back after (2026-10-30, found by PFSELFTEST).
- **Each copy gets a fingerprint** (`pfs:copy-fp`), which PFREFRESH compares to see if anything changed.
- **Structures only.** It never reads or changes pipes, and never writes inverts.
- **The tool never touches PFDEPTH.**
- **The plan record is the truth,** so rerunning is always safe.
