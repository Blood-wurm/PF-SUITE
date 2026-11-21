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
- **Which grid a point is in:** `pfg:at`, `pfg:pick`, `pfg:nearest`, `pfg:anchor-of`, `pfg:anchor-containing`, `pfg:usable`
- **The anchors read once — the index** (2026-11-20): `pfg:index`, and `pfg:nearest-in`, `pfg:copy-in-p`, `pfg:anchor-of-in`, `pfg:anchor-containing-in`, `pfg:usable-in`, which answer from it. See the rule below.
- **Grid top:** `pfg:top-lines`, `pfg:top-at` (nil when no line is found)

## Rules

- **Nothing here writes.** Making an anchor is pf-grid's job (PFSETUP, 2026-10-30).
- **The .cl comes from the anchor's `CL` attribute first,** then its V6 record, then V5's ledger. The tool writes CL when it creates the anchor; it is never typed.
- **The files and material:** the V6 records (pf-record XDATA: PRO-INV, PRO-TOP, TIN-EXIST, TIN-DESIGN, MATERIAL), then V5's FILES. V6 records are read through pf-record; V5's ledger directly.
- **The copy stamp:** V6's STAMP, then V5's META 302.
- **A copied anchor is one that shares its creation stamp with another anchor.** A unique stamp is never a copy, even when the drawing's handles were renumbered.
- **A loop reads the anchors once** (2026-11-20; the palette took a full minute). Each "which grid is this point in" used to search the drawing for anchors twice, once for the nearest box and once for the copy check. A run over every pipe therefore cost pipes × anchors × anchors. A loop now builds `pfg:index` once and calls the `-in` forms. A single call (`pfg:anchor-of`, `pfg:anchor-containing`) builds its own index. The answers are the same: same order, same nearest box, same copy rule. PFSELFTEST group 20 checks them against the old way. An index is a snapshot, so build it where nothing writes anchors (PFREFRESH's pipe loop, the palette), never across an anchor's change.
- **The grid top is V5's search:** the highest `PF-GRID-MJR` line above the station, per station. When there is none, the caller decides what to do.
