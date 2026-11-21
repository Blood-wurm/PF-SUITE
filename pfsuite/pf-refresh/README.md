# pf-refresh.lsp — PFREFRESH: update whatever changed

**Load position:** 12 (after pf-pipe).
**May depend on:** pf-cfg, pf-lib, pf-carlson, pf-record, pf-defaults, pf-anchor, pf-index, pf-draw, pf-struct, pf-pipe.
**Depended on by:** pf-palette (Refresh buttons, Edit Attributes, Defaults Save), pf-bench.

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

**The command is split** (2026-10-30): `pfu:main` asks the scope;
`pfu:run sc fmt pin` does the work and returns
`(checked updated skipped erased failed)`. `fmt` / `pin` nil = each block
resolves its own saved defaults (pf-defaults: line, utility, drawing,
built-in) -- the command. PFSELFTEST groups 9-11 hand in their own, Line
scope on their test lines, so no real block is written; groups 12 and 14 run
it with nil.

**"Would PFREFRESH change this?"** (2026-11-20). There is one test per kind
of block: `pfu:copy-due-p pe plan g fmt top ictx`, `pfu:pipe-due-p e g pin`
and `pfu:xing-due-p x ictx xextras`. Each compares the block's fingerprint
now against the one stamped on it last time. `pfu:run` calls them before
touching a block, and the palette calls the same three for its "needs
refresh" status, so the two always agree. PFSELFTEST group 20 checks that
after Refresh Line nothing on the line still needs one.

The orphan erase, the plan check and the unplaced list cover the scope only.
Each step's time is printed at the end (`MILLISECS`; `DATE` is only good to
the second since AutoCAD 2017).

Order of a run:
1. **Plan check:** a plan structure moved, turned or new since PFASSIGN last ran is named -- "run PFASSIGN first" (`pfm:stale`). It is not re-stationed here.
2. **Orphans and duplicates are erased,** each one named (Jake, 2026-10-16; restored 2026-11-17): a copy whose plan structure is gone, a copy whose plan record proves its line was removed, and a second copy of the same plan structure on the same line -- the **original (oldest handle) is kept**, the newer one erased. A copy with no plan link, or whose plan block exists but doesn't name that line yet, is **held and named for review**.
3. Profile copies whose source changed are moved, re-labelled, and their station line refitted. A structure renamed or re-stationed by PFASSIGN has its copies follow. A copy whose block no longer matches its plan block (a headwall changed size) is reported, not relabelled -- replace it.
4. Pipes whose source changed get their diameter, walls, label rows and leader redone. A pipe-label leader whose pipe is gone is erased.
5. A list of structures not placed yet, which is PFSTRUCT's job.

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

## Added 2026-11-20

- **Invert rows:** every profile copy's fingerprint now includes its invert rows (pf-invert): the pipes attached, the bottom on each side, the rows' text and place. A changed copy gets its rows rewritten after its label rows. After PFSTRUCT the first refresh writes the new copies' rows once.
- **Crossings (step 5b):** every PFSUITE_XING block in scope -- a Line scope takes crossings ON the line and crossings BY it -- is redone when a pipe at it changed (pf-xing). Everything the tool drew for a crossing whose block is gone is erased. Crossings short or unknown are listed at the end: `** N CROSSING(S) NEED A LOOK`. Refresh never finds new crossings -- that is PFXLABEL's.
