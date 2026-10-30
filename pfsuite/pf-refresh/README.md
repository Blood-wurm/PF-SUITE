# pf-refresh.lsp — PFREFRESH: update whatever changed

**Load position:** 12 (after pf-pipe).
**May depend on:** pf-cfg, pf-lib, pf-carlson, pf-record, pf-anchor, pf-index, pf-draw, pf-struct, pf-pipe.
**Depended on by:** nothing.

## What it owns

**PFREFRESH,** the one refresh for the whole drawing (Jake, 2026-10-16). It
covers every alpha block, profile CBI and pipe.
- When the tool writes a block, it stores a **fingerprint** (`SEEN`) of everything the block was built from.
- PFREFRESH recomputes the fingerprint:
  - **the same:** the block is left completely alone;
  - **different:** the block is updated, and the run says which.

PFSTRUCT and PFPIPE **place**. From then on, PFREFRESH **carries
everything on the profile**.

**Profile side only** (Jake, 2026-10-27). Which lines a plan structure is on,
its stations, face and name are PFASSIGN's. The run: PFASSIGN, PFSTRUCT,
PFREFRESH; after a plan edit, PFASSIGN then PFREFRESH.

**Scope** (Jake, 2026-10-27): it asks `Refresh [Selected/Line/Drawing] <Line>`.
Refreshing the whole drawing every time would lock up a big one.
- **Line** (default): the copies, pipes and leaders on one line's grids. Click anything on the line: a profile copy, a plan structure, a pipe, its leader, or the grid itself. The palette will hand the line over.
- **Selected:** the profile copies, pipes and leaders picked. A plan structure picked brings its copies.
- **Drawing:** everything.

The orphan erase, the plan check and the unplaced list cover the scope only.
The shared drafter inputs are read drawing-wide whatever the scope. Each
step's time is printed at the end (`MILLISECS`; `DATE` is only good to the
second since AutoCAD 2017).

Order of a run:
1. The shared drafter inputs, for structures and for pipes.
2. **Plan check:** a plan structure moved, turned or new since PFASSIGN last ran is named -- "run PFASSIGN first" (`pfm:stale`). It is not re-stationed here.
3. **Orphan and duplicate profile copies are erased,** and each one named. An orphan's alpha block is gone or off the line; a duplicate is a second copy of the same alpha block on the same line.
4. Profile CBIs whose source changed are moved, re-labelled, and their station line refitted. A structure renamed or re-stationed by PFASSIGN has its copies follow.
5. Pipes whose source changed get their diameter, walls, label rows and leader redone. A pipe-label leader whose pipe is gone is erased.
6. A list of structures not placed yet, which is PFSTRUCT's job.

## What changes count

| Block | Its fingerprint covers |
|---|---|
| Alpha block | where it sits, its rotation, its lines -- stamped by PFASSIGN; a difference is only reported here |
| Profile CBI | where it sits; the alpha's lines, rim, name, type, face and size; the shared inputs; the grid's numbers; the grid top there; the station line top; each label row's text and position |
| Pipe | its ends, size and material; the shared inputs; the grid's numbers; the drawn diameter; each label row's text and position; the state; the label grip (PFLEAD); its leader |

Names are written by PFASSIGN; a profile copy's fingerprint covers its alpha's name, so a renamed structure's copies follow.

## Rules: always left alone

- **Label text typed over by hand** (`pfr:refresh`).
- **Labels moved by hand** (`pfr:moved-p`). **But** a label sitting exactly where the block definition puts it was reset by ATTSYNC, and it is put back. ATTSYNC resets labels but leaves the stretched station line.
- **The barrel depth** (PFDEPTH).
- **The alpha blocks themselves:** PFREFRESH never writes them (PFASSIGN does).
- **Where a pipe label was dragged out of the pipe** (its PFLEAD grip). Its rotation, justification and leader are redone. Dragged anywhere **inside** the pipe, it goes back to the centre (2026-10-27).
- **Pipe ends:** read, never moved.
- **Anchors:** only read.

**It erases orphans and duplicates, but never places.** New profile copies
are PFSTRUCT's. Refresh lists any it finds.

**The first run on an existing drawing updates everything once,** because
nothing carries a fingerprint yet. After that, only what changed.
