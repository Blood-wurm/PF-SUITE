# pf-assign.lsp — PFASSIGN: the plan side

**Load position:** 9 (after pf-draw).
**May depend on:** pf-cfg, pf-lib, pf-carlson, pf-files, pf-record, pf-anchor, pf-index, pf-draw.
**Depended on by:** nothing.

## What it owns

**PFASSIGN,** drawing-wide. No grid pick, no selection (Jake, 2026-10-27).
It goes by line membership: pf-index's line tree finds every line every plan
structure is on, and PFASSIGN writes, on each structure that changed:
- its **name** (`BA-5/BC-1`), the line tree's (`pfm:names-put`);
- its **lines**, each with station and offset (MEMB), every line of its own utility;
- what it is: PFVIEW, PFTYPE, and PFSIZE from a sized block name;
- its **face** (CBI), read off its through-line (`pfm:face-of`);
- its **rim** from the grids' TINs, only when you say Yes.

The run: **PFASSIGN, PFSTRUCT, PFREFRESH.** After a plan edit: PFASSIGN, then
PFREFRESH.

## Rules

- **It stays** (Jake, 2026-10-22), and owns the plan side; PFREFRESH is profile only (2026-10-27).
- **Changed only.** A structure not moved, turned or put on another line since PFASSIGN last stamped it is left alone.
- **Moved:** re-stationed. **Left a line:** that line is dropped, and PFREFRESH erases its copy there.
- **Anything typed by hand is kept:** name, face, rim. A rim typed before the tool ever wrote one is marked as typed, not overwritten.
- **Rims:** one Yes/No per run, asked only when some grid has a TIN that can be found. Each rim comes off the TIN of the grid that shows the structure (its first line A–Z with one). Outside the surface, the rim is left as it is. Until V5's PFGL comes over.
- **Face:** one per structure, from the one line that runs on both sides of it. A structure at the very end of its only line, or with two lines running through it, is named in the run -- set PFFACE by hand.
- **Headwalls** (`*pf-count-only*`) take their number but are never assigned.
- One UNDO takes the whole run back.
