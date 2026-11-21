# pf-struct.lsp — PFSTRUCT: place the structures

**Load position:** 10 (after pf-assign).
**May depend on:** pf-cfg, pf-lib, pf-carlson, pf-record, pf-defaults, pf-anchor, pf-index, pf-draw.
**Depended on by:** pf-pipe (`pfs:ctx`, for the invert step later).

## What it owns

**PFSTRUCT: "place structures in profile"** (Jake, 2026-10-16). One command
for every structure type; it was called PFDRAW. **No grid pick:** it covers
every line in the drawing. Once the palette exists, it will take the line
clicked there.
1. grid by grid, **every alpha block on the line with no profile copy yet** gets one, on the grid that shows its station;
2. fills the new copy's drafter inputs (STA prefix etc.) from the saved defaults: line, utility, drawing, then built-in (pf-defaults);
3. writes its label rows, puts them at the grid top, and fits the station line to the **first** row.

**Copies already placed are left alone.** From then on, PFREFRESH carries
them: updates (an alpha block re-stationed by PFASSIGN included), and
erasing orphans and duplicates (the original copy is kept).

**The command is split** (2026-10-30): `pfs:main` reads the drawing;
`pfs:run plans grids top fmt` places and returns
`(placed already-placed skipped)`. `fmt` nil = each copy's saved defaults (the
command). `pfs:sync-fmt-in ents` builds explicit inputs over the blocks given;
only PFSELFTEST uses it now (group 8, so its test blocks never read the
drawing's saved defaults). Group 14 runs `pfs:run` with `fmt` nil on a
headwall and a sanitary MH. `pfs:main-for lname` is PFSTRUCT for
one line, the palette's New Structure button (2026-11-03); "no grid shows
this station" is reported only for the run's own lines.

## Label standard (Jake, 2026-10-16)

```
STA. 4+09.69 STORM LINE 'BA' =      PFSTAPRE + station + PFSTASUF; grid's own line first, then others A-Z
STA. 3+00.00 STORM LINE 'BC'        " =" on all but the last station row
CONST. CURB BOX INLET BA-5/BC-1     PFCONPRE + PFNAME + PFCONSUF, no size
                                    PFTEXT2: the drafter's, blank unless typed
G.L. 758.25                         PFELEVPRE + rim + PFELEVSUF
```

- **Built from the attributes only** (Jake, 2026-10-27): no wording from a table. The type's wording is PFCONPRE's default.
- **The inputs use line, utility, and drawing defaults** (Jake, 2026-11-17: keep this; it replaces the 2026-10-27 per-type push). A value typed in Edit Attributes on a profile copy stays on that copy. The palette's Defaults button (one line) and `PFDEFAULTS` (any scope) change saved defaults; `PFREFRESH` applies them to copies without hand edits.
- **Defaults per type** (`*pf-type-fmt*` in pf-cfg):

  | Type | PFCONPRE | PFELEVPRE |
  |---|---|---|
  | CBI, CBI-BOX | `CONST. CURB BOX INLET` | `G.L.` |
  | DBI | `CONST. DROP BOX INLET` | `T.G.` |
  | SMH | `CONST. SANITARY MH` | `T.R.` |
  | DMH | `CONST. DRAINAGE MH` | `T.R.` |
  | MH | `CONST. MANHOLE` | `T.R.` |
  | HDWL | `CONST. HDWL` | `INV.` (on `PFINV1`) |

  The rest: PFSTAPRE `STA.`, PFSTASUF `[util] LINE '[line]'`, PFCONSUF and PFELEVSUF blank.
- **A blank PFELEVPRE draws no top elevation row for other types.** Headwalls
  keep that row blank regardless of prefix. Their `PFELEVPRE` and
  `PFELEVSUF` control the `PFINV1` invert label below the profile symbol.
- **A block without PFELEVPRE yet** uses its type's default, and the run says so: BEDIT it, PFMKATT, then ATTSYNC.
- **`CONST.` is a retired default.** A structure still holding the `CONST.` the tool wrote, never retyped, gets its type's new default. Anything typed is kept.
- **Any row can be typed over,** and it's kept.
- **The suffix comes from the .cl name:** `[util] LINE '[line]'`, split at the first underscore.
- **No grid top at a station:** say so, and put the labels `*pf-top-default*` text heights above the structure.
- **No rim yet** (Jake, 2026-11-13): the copy is still placed, **on the grid's top line** at its station (`pfs:copy-y`), and its elevation row reads `G.L. XXX.XX`. A headwall instead shows `INV. XXX.XX` below its profile symbol. Type a rim or headwall flowline (Edit Attributes or Properties) and the next refresh moves the copy down to it. **No rim and no top line at that station:** skipped, and said. PFREFRESH no longer skips a structure for having no rim.

## Rules

- **A label row moved by hand is left where it is.** A row reset by ATTSYNC, sitting at its block position, is put back. Refitting PFTOP rebuilds the insert and can carry a moved row with it, so its spot is noted first and it is put back after (2026-10-30, found by PFSELFTEST).
- **Each copy gets a fingerprint** (`pfs:copy-fp`), which PFREFRESH compares to see if anything changed.
- **Structures only.** It never reads or changes pipes. A headwall alone writes
  its `PFINV1` display from the manually entered flowline in `PFRIM`; the
  pipe-derived invert labels for other structures remain future work.
- **The headwall invert sits `*pf-inv-drop-factor*` text heights below the
  lowest geometry showing** -- the copy's own lines and its nested profile
  symbol (`pfl:nested-bottom`), read off the insert, so no nested block name
  is coded here. Nothing found: below the flowline. A `PFINV1` moved by hand
  is left where it is.
- **Sizes:** a lookup block copies `PFSIZE_LU`; a sized name (`PFSUITE_HDWL_18`,
  `PFSUITE_HDWL_24x36`) gives `PFSIZE` from the name; the sanitary MH copies
  the plan's `PFSIZE`, keeping one typed on the copy.
- **The tool never touches PFDEPTH,** or the sanitary MH's `PFFLOORDWN` (the
  drafter's floor drop).
- **The sanitary MH's cone is its PFSIZE** (2026-11-19). The drafter types
  `48x24`, `48x30` or `48x36` on the plan block; each copy is set to that
  profile state, the way a CBI's face picks its state. Any case, spaces
  ignored. A size that is no cone is reported: a new copy shows `48x24`, an
  old one keeps its cone. PFREFRESH follows a cone changed on the **plan**
  block; a cone typed only on the copy shows on the next run that has
  something else to update.
- **The plan record is the truth,** so rerunning is always safe.

## Added 2026-11-20

- **A face per line:** `pfs:face-for` -- a PFFACE typed on the plan block wins; else the copy's own line's face from MEMB; else the plan's PFFACE. The copy's PFFACE attribute is written with it.
- PFSTRUCT says the new copies' invert rows come with the next PFREFRESH (the palette's New Structure runs it).
