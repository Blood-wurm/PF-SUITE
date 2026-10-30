# pf-pipe.lsp — PFPIPE: the profile pipe

**Load position:** 11 (after pf-struct).
**May depend on:** pf-cfg, pf-lib, pf-record, pf-anchor, pf-draw, pf-struct.
**Depended on by:** pf-bench.

## What it owns

- **PFPIPE:** two clicks, the upstream invert then the downstream invert. `S` changes the size, `M` the material.
- **Reading Carlson's pipe libraries at run time:**
  - `pipesize.dta`: **round pipe only**, where the first field is the shape and `0` means round;
  - `pipen.dta`: the materials.
- **Reading a placed pipe:** its ends, size and material.
- **`pfp:update`:** the pipe's diameter and walls, plus its **two-row label** (Jake, 2026-10-16):
  ```
  PFLABEL   PFLENPRE length PFLENSUF size        CONST. 45 L.F. ~ 15"
  PFLABEL2  material PFSLOPEPRE slope PFSLOPESUF ADS N-12 HDPE @ 5.5%
  ```
  - **Rounding:** the length in whole feet, the slope to 0.1%.
  - **Placement:** both rows run along the pipe, straddling its centre 2.0 text heights apart (V5's spacing).
  - **Typed over:** each row is its own. A row typed over by hand is kept.
  - **Dragged:** the label's grip is `PFLEAD`, which carries both rows. A label dragged **outside** the pipe stays where it was put, turns level and goes on a leader (Jake, 2026-10-22). One dragged anywhere **inside** the pipe goes back to the centre, along the pipe, as if never dragged (Jake, 2026-10-27). Every run redoes rotation, justification, state and leader.
- **The leader** is drawn by the tool, not held in the block: one polyline per pipe, its tapered first segment the arrowhead, tagged with the pipe's handle (XDATA `PIPE`). `pfp:leader-verts` works out its points, `pfp:leader-put` erases the old one and draws the new. Sizes are in pf-cfg, at 1"=20'.
- **`pfp:sync`:** the four label inputs are **shared**. A change on any pipe goes to every pipe, through pf-record's `pfr:sync-inputs`.
- **The invert helpers** (`pfp:inverts` and so on), kept for the invert-label step and **not called yet**.

## Public API

`pfp:sizes`, `pfp:mats`, `pfp:wall`, `pfp:all`, `pfp:ends`, `pfp:size`,
`pfp:mat`, `pfp:sync`, `pfp:sync-in`, `pfp:rows`, `pfp:update`, `pfp:place`,
`pfp:to-world`, `pfp:to-local`, `pfp:pt-get`, `pfp:inside-p`

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
