# pf-invert.lsp — the invert rows

**Load position:** after pf-pipe, before pf-xing and pf-refresh.
**May depend on:** pf-cfg, pf-lib, pf-record, pf-defaults, pf-anchor, pf-index, pf-draw, pf-struct, pf-pipe.
**Depended on by:** pf-xing, pf-refresh, pf-bench.

## What it owns

Port step 4 (Jake, 2026-11-13 and 2026-11-20). **No command:** PFREFRESH
writes each profile copy's `PFINV1..5`, changed copies only. The palette's New
Structure runs the line's refresh after placing, so new copies get theirs at
once; after a typed PFSTRUCT, run PFREFRESH.

Each row is V5's: `I.O. 745.10 (15")`.

| Where | Row |
|---|---|
| A pipe attached | That pipe **end's** elevation, with its size. The pipe block is the truth — a pipe can come in above the floor (a drop) |
| No pipe on a side | The structure's **bottom** on that side, no size — only where the line carries on past the structure that way |

- **Which pipe belongs to which structure:** a pipe end at the structure's wall — within `*pf-inv-wall-tol*` (1 ft) sideways — anywhere from the bottom up to the rim. The nearest wall wins.
- **Inlet or outlet:** downstream is LEFT. An end at the left wall is the outlet (I.O.), at the right wall the inlet (I.I.). An end exactly on the station line goes by which end of the pipe it is.
- **The bottom** is read off the copy, never nudged: the outer walls' lowest point on each side (`pfl:walls`). The CBI's walls are at `PFBARREL_R`; the sanitary MH's at 2 ft (its 48" barrel), so its left side is the `PFFLOORDWN` corner and its right the `PFDEPTH` end.
- **A pipe end below the bottom** is reported, never moved. Above it is a drop and is fine.
- **A junction:** the other lines' pipes, read on their own copies and grids, go in the middle columns; one leaving takes the I.O. column when this line has none (V5).
- **Layout (V5's pfinvert):** turned to read up, hanging from one baseline `*pf-inv-drop-factor*` (4) text heights below the lowest invert, `*pf-inv-gap-factor*` (2) apart, centred on the station. The line's most downstream structure is pushed right: STORM 2.5 past its downstream invert, SANITARY 2.0 off the grid's left edge (`*pf-inv-first-shift*`, flat units).
- **Typed over** — kept. **Dragged** — left there (measured from the bottom, so a PFDEPTH drag that carries the rows isn't a hand move).
- **The headwall** keeps its own `PFINV1` (its flowline, pf-struct).
- More than five rows: the rest are not shown, and said.

## Public API

`pfi:ctx` (the run's grids, pipes, copies, line minimums, grid tops),
`pfi:c`, `pfi:geo`, `pfi:forget`, `pfi:atts`, `pfi:rows`, `pfi:layout`,
`pfi:fp`, `pfi:update`, `pfi:pipes`, `pfi:grid-of`, `pfi:same-grid-p`,
`pfi:barrel-r`

## Not done yet

- **Recording the inverts on the PLAN block** (for Edit Attributes and PFEXPORT): the rows live on the profile copies. Writing them on the plan block needs hidden plan attributes (the PFINV tags are visible ones), and adding them to the export needs the Pro-Flow importer to agree. Left for a decision.

PFSELFTEST group 16.
