# pf-grid.lsp — PFSETUP and PFREMOVE: the grid anchors

**Load position:** 13 (after pf-refresh).
**Prefix:** `pfn:` (`pfx:` is pf-export's).
**May depend on:** pf-cfg, pf-lib, pf-carlson, pf-files, pf-record, pf-anchor, pf-index, pf-draw, pf-struct, pf-pipe.
**Depended on by:** pf-bench (PFLINETEST's anchor checks, PFSELFTEST group 5).
**Files:** `pf-grid.lsp`, `pf-grid.dcl` (the record dialog, V5's `pfsetup_main`).

Ported from V5's `pfsetup.lsp` and `pfanchor.lsp`, mostly as-is (Jake, 2026-10-30).

## What it owns

**PFSETUP** asks `[Scan/Anchor/Edit] <Scan>`. The palette will call the same pieces later.
- **Scan** (V5's AUTO):
  - reads the grid-name text on layer `PF-NAME` (`STORM LINE 'DA'`), formatting codes stripped first (`%%U` underline and the like, `pfl:plain-text`);
  - finds `TYPE_NAME.cl` in the Alignments folder and the `_INV` / `_TOP` `.pro` pair in the Profiles folder;
  - writes a **stub** for each line: a line known before its grid is anchored, in V5's drawing-dictionary format, which the line tree reads.
  - It then checks every anchor and prints what it finds.
- **Anchor:** pick a stub from the list (or 0 for a blank form), fill in the dialog, then pick the grid's lower-left and top-right corners.
- **Edit:** click a grid, change the dialog, and it's rewritten in place.

**PFREMOVE** asks you to click a grid, lists what's on it, then asks `Remove [Anchor/Everything] <Anchor>` and confirms (No is the default).
- **Anchor:** erases only the anchor. The profile copies, pipes and leaders on the grid stay, **released**: the suite never touches them again. Without that, a refresh would erase the copies as orphans and re-label the pipes against the nearest *other* grid.
- **Everything:** erases those too.
- A copied anchor: offers to erase just the copy.

## The anchor

- **The block:** your `PFSUITE_ANCHOR`, inserted at the lower-left corner on layer `PF-ANCHOR` (created no-plot, colour 152, only if missing). The icon is scaled HPLOT / 50, V5's rule, and sent behind the grid.
- **Attributes:** every V5 tag plus CL: LINE, UTIL, STA0, DATUM, HPLOT, VPLOT, WIDTH, HEIGHT, CL. The definition is **checked first**; a block missing any is refused and named. PFMKANCATT (pf-bench) adds them in BEDIT.
- **Records** (pf-record XDATA): CL, PRO-INV, PRO-TOP, TIN-EXIST, TIN-DESIGN, MATERIAL, SUMS (checksums of the `.cl` and `.pro` pair), STAMP (its own handle), SCHEMA. TINs aren't checksummed (binary, large).
- **STA0** is the `.cl`'s first station, as V5 did it.
- **V5's anchors** are still read through their ledger (`pfg:grid`). Editing one gives it V6 records.

## Rules (V5's, kept)

- **The name is the identity key.** Picked files validate against it; they never set it.
- **Pairs bind both-or-neither:** `.pro` INV/TOP, TIN existing/design.
- **Scan never guesses:** no `.cl`, or two matching, is reported and skipped. It fills empty `.pro` slots only, never overwriting one.
- **Edit refuses:**
  - a new name or utility (that's a new grid: PFREMOVE, then Anchor);
  - a `.cl` with a different station range (a rebuild, not a swap).
- **Anchor checks** (`pfn:checks`, also in PFLINETEST):
  - a copied anchor;
  - unreadable numbers;
  - the `.cl` missing or unreadable;
  - a `.cl` or `.pro` changed since setup (its checksum);
  - the CL attribute disagreeing with the record;
  - no grid line at the anchor's corner (the grid moved without it);
  - the top at the right edge differing from setup (stretched or redrawn).

## Dropped from V5

The GEOM / twin caches, pass and status records, the index repair and the XFORM stamp. The line tree, PFASSIGN and the fingerprints do those jobs now.

## Asking and doing are split (2026-10-30)

The dialog and the picks ask; these do the work, given the answers -- what PFSELFTEST drives:
- `pfn:scan-in cdir pdir sn`: Scan over the folders and grid names given (`pfn:scan` = the project's folders, the sheet's names);
- `pfn:place-rec rec stub`: Anchor, `rec` complete with its corners; returns the anchor or the refusal;
- `pfn:edit-check anchor rec`: Edit's refusals (a string), `'UNKNOWN` (go ahead, ranges not compared) or nil (go);
- `pfn:edit-write anchor rec pts`: Edit's write; `pfn:corners` gives the corners on record;
- `pfn:remove anchor mode objs`: PFREMOVE's work (`pfn:on-grid` lists `objs`).

For the palette (2026-11-03): `pfn:refusal` (metric / no Carlson, shared with the command), `pfn:scan-run` (Scan plus every anchor's checks, printed), `pfn:remove-ask anchor` (PFREMOVE after the click: the listing, `[Anchor/Everything]`, the confirm).

## Tests

- **PFSELFTEST group 5:** the naming helpers, the refusal cascade, a test anchor written and read back (attributes, layer, icon scale, every record), a COPY caught, a changed `.pro` caught, CL typed over caught, PFREMOVE Anchor (released, invisible to the suite) and Everything, the stub store, and a V5 anchor still read.
- **Group 6:** Scan on a scratch folder (named, `.pro` pair bound, no `.cl` skipped, nothing named twice, grid-name text read), Anchor from a stub and from a blank form (stub gone, STA0, every check passes, the same line refused), Edit (new name refused, different range refused, a change written in place), a copied anchor named by the checks.
- **Group 11:** after PFREMOVE Anchor, PFREFRESH leaves the released copy alone and PFASSIGN drops the line from the structure's name.
