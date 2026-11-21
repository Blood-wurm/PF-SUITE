# pf-pipe.lsp — PFPIPE: the profile pipe

**Load position:** after pf-struct.
**May depend on:** pf-cfg, pf-lib, pf-mats, pf-record, pf-anchor, pf-draw, pf-struct.
**Depended on by:** pf-invert, pf-xing, pf-refresh, pf-grid, pf-export, pf-palette, pf-bench.

## What it owns

- **PFPIPE:** two clicks, the upstream invert then the downstream invert. `S` changes the size, `M` the material.
- **Sizes and materials come from the pipe table** kept with the lisp, `pf-cfg\pf-pipes.csv` (pf-mats; Jake, 2026-11-20). Carlson's `pipesize.dta` / `pipen.dta` are no longer read.
  - The material list is the table's materials **for the clicked grid's utility**; the first material is the table's **Default** for that utility, else the one PFSETUP recorded on the grid.
  - The size list is the chosen material's sizes.
- **Inside and outside diameter on the block:** hidden `PFID` / `PFOD`, filled from the table when the pipe is placed and whenever its size or material changes (`pfp:dims-put`). A value typed over is kept. **The block is the source of truth:** `pfp:dims` reads them; inverts and crossings use it. A blank `PFOD` = wall unknown.
- **Reading a placed pipe:** its ends, size, material, inside and outside diameter.
- **`pfp:update`:** the pipe's diameter (its **inside** diameter, `PFID`) and walls (from `PFOD`), plus its **two-row label** (Jake, 2026-10-16):
  ```
  PFLABEL   PFLENPRE length PFLENSUF size        CONST. 45 L.F. ~ 15"
  PFLABEL2  material PFSLOPEPRE slope PFSLOPESUF ADS N-12 HDPE @ 5.5%
  ```
  - **Rounding:** the length in whole feet, the slope to 0.1%.
  - **Placement:** both rows run along the pipe, straddling its centre 2.0 text heights apart (V5's spacing).
  - **Typed over:** each row is its own. A row typed over by hand is kept.
  - **Dragged:** the label's grip is `PFLEAD`, which carries both rows. A label dragged **outside** the pipe stays where it was put, turns level and goes on a leader (Jake, 2026-10-22). One dragged anywhere **inside** the pipe goes back to the centre, along the pipe, as if never dragged (Jake, 2026-10-27). Every run redoes rotation, justification, state and leader.
- **The leader** is drawn by the tool, not held in the block: one polyline per pipe, its tapered first segment the arrowhead, tagged with the pipe's handle (XDATA `PIPE`). `pfp:leader-verts` works out the arrow's tip; the shape is `pfl:leader-path` in pf-lib, shared with the crossing label. `pfp:leader-put` erases the old one and draws the new. Sizes are in pf-cfg, at 1"=20'.
- **Defaults:** the four label inputs inherit drawing, utility, and line defaults. A value typed on a pipe is kept on that pipe. `pfp:sync` remains for diagnostic cases with explicit inputs; the production command resolves defaults per pipe.
- **The invert rows** moved to pf-invert (2026-11-20); `pfp:inv-row` (V5's row format) stays here.

## Public API

`pfp:sizes`, `pfp:mats`, `pfp:wall` (kept for PFSETUP / PFCONVERT / the bench,
now over the table), `pfp:all`, `pfp:ends`, `pfp:size`, `pfp:mat`,
`pfp:dims`, `pfp:dims-table`, `pfp:dims-put`, `pfp:sync`, `pfp:sync-in`,
`pfp:rows`, `pfp:update`, `pfp:place`, `pfp:to-world`, `pfp:to-local`,
`pfp:pt-get`, `pfp:pt-put`, `pfp:put`, `pfp:inside-p`, `pfp:inv-row`,
`pfp:grid-of-ends`, `pfp:grid-issue`, and their `-in` forms
(`pfp:grid-of-ends-in ends idx`, `pfp:grid-issue-in ends expected idx`).
A loop over pipes builds one anchor index (`pfg:index`) and passes it to the
`-in` forms; PFREFRESH's pipe loop and the palette do (2026-11-20).

**The command is split** (2026-10-30): `pfp:main` asks (size, material, the
two clicks); `pfp:place p1 p2 g size mat others` does the work. `others` is
the pipes whose label inputs this one shares: `T` = every pipe (the command).
PFSELFTEST group 10 calls `pfp:place` with its own pipes.

## Rules

- **The pipe's ends are the truth.** Which structures it connects is worked out from where the ends are.
- **The block is `PFSUITE_PIPE`.** The visibility states are `WALL OFF` and `WALL ON`.
- **A leader belongs to the pipe whose handle it carries.** PFREFRESH erases a leader whose pipe is gone, and a second leader for one pipe (left by a COPY) when that pipe is redone.
- **"Dragged" is read from `PFLEAD`, never from the rows.** ATTSYNC resets the rows but not the grip, so a dragged label survives it. The tool remembers `PFLEAD` (POS, under its own name) only when it chose the spot itself, so a dragged label stays dragged from run to run.
- **The rows are placed last.** Every dynamic-property write rebuilds the insert and can shift them.
