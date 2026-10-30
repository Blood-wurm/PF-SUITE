# pf-index.lsp — which lines a structure is on

**Load position:** 7 (after pf-anchor).
**May depend on:** pf-cfg, pf-lib, pf-carlson, pf-files, pf-record, pf-anchor.
**Depended on by:** pf-assign, pf-struct, pf-refresh, pf-bench.

## What it owns

**Membership,** stored **on the structure** (MEMB), not on the line. This
follows V5's `pfanchor/INDEX-DESIGN.md`: index the structure, not the line. A
structure with two entries is a junction. PFASSIGN writes it for every line at
once, drawing-wide, with no pick (Jake, 2026-10-27).

**V5's line tree** (ported 2026-10-22):
- **the lines:** every grid's `.cl`, plus V5's grid-less "stubs" in the drawing's `PFTOOLS` dictionary. One entry per `.cl`;
- **numbers:** each structure numbered along each line it is on, **lowest station = 1**;
- **names:** its lines A to Z as `LINE-number`, joined by "/", e.g. `BA-5/BC-1`. Only lines of the structure's own utility (its nearest line's); another utility meeting it is a crossing.

PFASSIGN writes the names as tool values, then each structure's lines, face
and rim. A value typed by hand is kept.

**Reading the `.cl` file** (V5's `pf:cl-parse`). Where a point sits on a line
is measured against the file, not asked of Carlson:
- **The bend fix.** Carlson's `cl_location_at_pt` answers nothing for a point just past a bend, and V5 dropped those structures silently, its one critical open bug. The nearest segment of the read `.cl` always answers; at a bend, that is the bend.
- **Checked against Carlson.** Each reading's end stations and first point are compared with Carlson's. A file that fails, or has a row the reader doesn't know, is **walked** through Carlson every 2 ft instead, and a structure close to a walked line is located through Carlson exactly.
- **Kept for the session,** keyed by the file's path, date and size. Nothing is written to the drawing.

## Public API

- `pfm:geom`, `pfm:where`: a `.cl`'s points with stations, and where a point is against them
- `pfm:lines`: the line table, with notes on lines left out
- `pfm:hits`: V5's membership rule. On a line means within 0.15' and inside its station range, ±0.01'. Measured against the read `.cl`
- `pfm:tree`: every plan structure's lines, near misses, and the station index
- `pfm:name`: the built name
- `pfm:names-put`: **writes** the changed names; says what changed and what is near a line but not on it
- `pfm:face`, `pfm:face-of`: which faces of a CBI a line goes through; the structure's one face, off its through-line
- `pfm:assign`: **writes** PFVIEW, PFTYPE, PFSIZE (sized names only), MEMB (every own-utility line) and PFFACE -- only on a structure that changed
- `pfm:rim-put`: **writes** PFRIM off the loaded TIN; a typed rim is kept
- `pfm:stale`: plan structures moved or new since PFASSIGN last ran (PFREFRESH reports them)

## Rules

- **Anything a drafter typed is kept** (`pfr:refresh`).
- **Nothing is dropped without a reason.** A structure within 1.0' of a line but not within 0.15' is named in the run.
- **Stacked structures are named.** Two plan structures within 0.5' of each other (one drawn on top of the other) would share a number; PFREFRESH and PFLINETEST say so (`pfm:stacked`).
- **Headwalls count.** V5 numbers them and V5 is right (Jake, 2026-10-27). Until `PFSUITE_HDWL` exists, the blocks in `*pf-count-only*` (pf-cfg: `HDWL`, `HDWL_<size>`) take their number on a line but are never named, placed, refreshed or erased (`pfm:others`). **Empty that list once PFSUITE_HDWL is built.**
- **Otherwise only `PFSUITE_` blocks are counted.** A V5 structure block still on a line is skipped until it is replaced (PFREPLACE) or its type exists in V6.
