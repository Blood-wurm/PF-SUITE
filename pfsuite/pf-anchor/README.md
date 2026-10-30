# pf-anchor.lsp — the profile grids (READ ONLY)

**Load position:** 6 (after pf-record).
**May depend on:** pf-cfg, pf-lib, pf-files.
**Depended on by:** pf-index, pf-assign, pf-struct, pf-pipe, pf-bench.

## What it owns

Reading the anchor at each grid's lower-left corner. It reads
`PFSUITE_ANCHOR` and V5's `PF-ANCHOR` / `PF-GRIDANCHOR` the same way. You
click inside a grid and everything comes from its anchor: stations, datum,
plot scales, size and the .cl.

## Public API

- **Finding anchors:** `pfg:all` (dynamic `*U` copies included), `pfg:atts`, `pfg:att`
- **Stored records:** `pfg:extdict`, `pfg:rec` (V5's ledger), `pfg:v6` (V6's records), `pfg:stamp`, `pfg:copy-p`, `pfg:cl-att`
- **The grid:**
  - `pfg:grid`, `pfg:title`, `pfg:text-ht`
  - `pfg:sta-range`, `pfg:on-grid-p`
  - `pfg:cl`, `pfg:line-name`
- **Which grid a point is in:** `pfg:at`, `pfg:pick`, `pfg:anchor-of`
- **Grid top:** `pfg:top-lines`, `pfg:top-at` (nil when no line is found)

## Rules

- **Nothing here writes.** Making an anchor is pf-grid's job (PFSETUP, 2026-10-30).
- **The .cl comes from the anchor's `CL` attribute first,** then its V6 record, then V5's ledger. The tool writes CL when it creates the anchor; it is never typed.
- **The files and material:** the V6 records (pf-record XDATA: PRO-INV, PRO-TOP, TIN-EXIST, TIN-DESIGN, MATERIAL), then V5's FILES. V6 records are read through pf-record; V5's ledger directly.
- **The copy stamp:** V6's STAMP, then V5's META 302.
- **A copied anchor is one that shares its creation stamp with another anchor.** A unique stamp is never a copy, even when the drawing's handles were renumbered.
- **The grid top is V5's search:** the highest `PF-GRID-MJR` line above the station, per station. When there is none, the caller decides what to do.
