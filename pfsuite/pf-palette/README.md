# pf-palette.lsp — PFPALETTE: the palette

**Load position:** 14 (after pf-grid, before the bench).
**Prefix:** `pfw:` (`pfp:` is pf-pipe's).
**May depend on:** every module above it.
**Depended on by:** pf-bench (PFSELFTEST group 12).
**The form:** `pfsuite-odcl\pfsuite.odcl` — V5's project, edited by Jake in OpenDCL Studio (2026-11-03). Code never edits it.

## What it owns

`PFPALETTE` shows or closes the palette. `PFPRELOAD` re-reads the `.odcl` — **run it after every Studio save**.

**Three guards** (2026-11-03, after the first open showed `consp nil :error#2` and a click called V5's `btnSetup`):
- **Forced re-read:** the first PFPALETTE after pf-load re-reads the `.odcl` with `dcl-Project-Load`'s force argument. Without it OpenDCL keeps a project already loaded this session — V5's, or the one from before a Studio save.
- **Control census:** on open, any control the code uses that the loaded form lacks is named, and V5's `btnSetup` being present says the old project is loaded. It only reads whether each control symbol exists — no property call.
- **Named errors, with a trail:** every handler runs through `pfw:guard`. Each step marks itself (`pfw:mark` / `pfw:stage`), and an error prints `PFPALETTE: <handler> stopped: <message>`, then `steps: a > b > c` (the last ten; the last one is where it broke) and the command's own last stage; an undo group it left open is closed. Guards nest — a tree's SelChanged firing inside a button's repaint adds to the button's trail, it doesn't wipe it. The open path is guarded too.

| Tab | Tree | Panels | Buttons |
|---|---|---|---|
| **Setup** | `tvwLines` | `metaList` (type, line, grid?, stations, datum, scales, material), `lvwLinkage` (the bound `.cl`, `.pro` pair, TINs) | Scan, Anchor, Edit, New, Remove, Zoom To, Index |
| **Run** | `tarLines` | `detailsList` (the same summary), `lvwCommand` (columns only, for later) | Assign, New Structure, New Pipe, Refresh Line, Refresh All |
| **Tools** | — | — | room to grow (PFPRO, exports) |

The trees are read from the anchors and the stubs only — no `.cl` is opened and no structure is read to draw them. A line Scan named but not anchored shows `-- no grid yet`.

| Button | Runs | Needs |
|---|---|---|
| Scan | PFSETUP Scan, then every anchor's checks | — |
| Anchor | PFSETUP Anchor from the picked line's stub: the dialog, the two corners | a line with no grid yet |
| New | PFSETUP Anchor on a blank form | — |
| Edit | PFSETUP Edit on the picked line's grid | a gridded line, not a copy |
| Remove | PFREMOVE on the picked line's grid: what's on it, [Anchor/Everything], confirm | a gridded line |
| Zoom To | the grid; a line with no grid yet, its path in plan | a line |
| Index | says it has no V6 job yet | — |
| Assign | PFASSIGN for the picked line: names, lines, faces written for **that line's** structures only (`pfa:line`) | a line |
| New Structure | PFSTRUCT for the picked line (`pfs:main-for`) | a gridded line |
| New Pipe | PFPIPE | — |
| Refresh Line | PFREFRESH, Line scope, the picked line | a line |
| Refresh All | PFREFRESH, the whole drawing | — |

Each repaints the palette afterwards. The trees come back with **nothing picked**, as in V5: `pfw:refresh` clears the picks first (a rebuilt tree makes them stale) and runs the whole fill inside one catch. Re-picking the last line was tried first; its read-back, outside the catch, stopped every open with `consp nil` (2026-11-03).

## The one change from V5

A button that changes the drawing has **Event Invoke = 1** ("Allow Command") in Studio, so its handler runs **as a command** and calls the work directly inside `pfd:run` — one undo group, the stage named on an error. V5 queued commands with `vla-SendCommand` and a ticket dispatcher; its first queued command of a session died at its own prompt (V5 OPEN-ISSUES). That channel is not ported.

Event Invoke's meaning comes from OpenDCL forum threads and the vendor's AUBlockTool sample (its palette button calls `getpoint` and `(command)` directly), not the reference page — the CAD test below settles it.

## Studio settings (Jake's)

| Control | Event Invoke | Events ticked |
|---|---|---|
| the form `pfsPalette` | — | Initialize |
| `tvwLines`, `tarLines` | 0 | SelChanged |
| `btnScan` `btnAnchor` `btnEdit` `btnNew` `btnRemove` `btnAssign` `btnStruct` `btnPipe` `btnRefreshLine` `btnRefreshAll` | **1** | Clicked |
| `btnZoom`, `btnIndex` | 0 or 1 | Clicked |
| `btnRefresh`, `btnHelp` (V5's footer, if kept) | 0 | Clicked |
| `metaList` `lvwLinkage` `detailsList` `lvwCommand` | — | none |

`lblCounts`, if the form still has it, shows "N lines (M with grids)".

## Rules (V5's, each paid for in CAD — `pfsuite-odcl\OPENDCL-WIRING.md`)

- Columns are added in **OnInitialize only** — AddColumns stacks.
- Data is filled **after** `dcl-Form-Show` — OnInitialize fires before the window exists.
- An undefined control symbol is nil and `dcl-*` on nil does nothing: caption and list writes are guarded.
- Never call a property the control type doesn't document — a missing one raises a modal no catch can stop.
- Tree selection handlers only **read**.
- A refused button always says why (`pfw:need`).
- `*pfw-filling*` is set while a tree is rebuilt: AddParent / AddChild fire SelChanged against a map not built yet.

## Not yet

- Line-limited reads: Assign builds the line tree over the whole drawing (it writes only the picked line); New Structure and Refresh Line read the drawing's structures to find the line's. Next step.
- Per-line prefixes and suffixes (Jake, 2026-11-03).
- `lvwCommand` and the Run tab's counts; the Tools tab; rims from the TIN (port step 5).

## Tests

PFSELFTEST group 12: the tree's rows (a gridded line, a line with no grid yet), the panels (datum, stations, the `.cl`, a stub's `.pro`, "(not set)"), and the refusals. Group 7 covers Assign for one line. The buttons themselves are clicked by hand (FIRST-VERSION-TESTS §2).
