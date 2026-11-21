# pf-palette.lsp — PFPALETTE: the palette

**Load position:** 14 (after pf-grid, before the bench).
**Prefix:** `pfw:` (`pfp:` is pf-pipe's).
**May depend on:** every module above it.
**Depended on by:** pf-bench (PFSELFTEST group 12).
**The form:** `pfsuite-odcl\pfsuite.odcl` — V5's project, edited by Jake in OpenDCL Studio (2026-11-03). Code never edits it.

## What it owns

`PFPALETTE` shows or closes the palette. `PFPRELOAD` re-reads the `.odcl` — **run it after every Studio save**.

**The Defaults dialog and `PFDEFAULTS`** (moved here from pf-defaults, 2026-11-17, so the load order holds: they read structures, grids and pipes and run PFREFRESH). Functions `pfw:dflt-*`; the OpenDCL handlers keep their Studio names (`c:pfsuite/pfsDefaults/...`). Saving and looking up the defaults stays in pf-defaults (`pfv:`). The dialog's contract and Studio wiring: [pf-defaults README](../pf-defaults/README.md).

For AutoCAD 2027, install OpenDCL Studio/Runtime 9.3.3.1 or newer. The installed
9.1.5.2 runtime has no AutoCAD 2027 module, so `OPENDCL` is unknown and the
`dcl-*` functions are unavailable. Save and close Studio before updating it,
then restart AutoCAD. `PFPALETTE` reports the missing runtime without calling
`dcl-Project-Load`.

**Three guards** (2026-11-03, after the first open showed `consp nil :error#2` and a click called V5's `btnSetup`):
- **Forced re-read:** the first PFPALETTE after pf-load re-reads the `.odcl` with `dcl-Project-Load`'s force argument. Without it OpenDCL keeps a project already loaded this session — V5's, or the one from before a Studio save.
- **Control census:** on open, any control the code uses that the loaded form lacks is named, and V5's `btnSetup` being present says the old project is loaded. It only reads whether each control symbol exists — no property call.
- **Named errors, with a trail:** every handler runs through `pfw:guard`. Each step marks itself (`pfw:mark` / `pfw:stage`), and an error prints `PFPALETTE: <handler> stopped: <message>`, then `steps: a > b > c` (the last ten; the last one is where it broke) and the command's own last stage; an undo group it left open is closed. Guards nest — a tree's SelChanged firing inside a button's repaint adds to the button's trail, it doesn't wipe it. The open path is guarded too.

| Tab | Tree | Panels | Buttons |
|---|---|---|---|
| **Setup** | `tvwLines` | `metaList` (type, line, grid?, stations, datum, scales, material), `lvwLinkage` (the bound `.cl`, `.pro` pair, TINs) | Scan, Anchor, Edit, New, Remove, Zoom To, Index |
| **Run** | `tarLines` | `detailsList` (the same summary), `lvwCommand` (the line's structures and pipes in station order) | Assign, New Structure, New Pipe, Refresh Line, Refresh All, Edit Attributes, Defaults |
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
| Edit Attributes | For a picked structure, EATTEDIT opens its **plan block** and then its **profile copy**. For a picked pipe, it opens that pipe's attributes. It then runs PFREFRESH Line. Typed label values remain local overrides. Pipe size is set through `PFSIZE_LU` in AutoCAD Properties. | a structure or pipe picked in its list |
| Defaults | Opens the modal PFSUITE Defaults dialog for the picked line; Save updates that line's defaults and refreshes it | a gridded line |

**The Run list** uses the existing `lvwCommand` List View. Picking a line fills it with structures and pipes together, ordered by starting station. Its columns are **Item**, **Station(s)**, and **Status**. A structure row shows its name and placement status. A pipe row starts with **Pipe**, then shows its actual size and material; the station cell shows both ends. A List View here has **Clicked**, `(Row Column)`, with zero-based row numbers. Clicking a row records that exact block; clicking empty space leaves the pick alone. **Edit Attributes** opens AutoCAD's own dialogs for the picked structure or pipe, then refreshes the line. A structure opens its plan block and profile copy; a pipe opens its own attributes. Pipe size is set through `PFSIZE_LU` in AutoCAD Properties. The list refills after editing, and the line stays picked.

Pipe rows appear when **both ends are inside the same usable grid** of the picked line. Their Status says **Hand edited** when a prefix, suffix, or displayed label row was explicitly edited or differs from what the suite last wrote. **Unverified** means a label attribute has no provenance record; **Missing fields** means a required label attribute is absent. Size and material are expected to vary between pipes and do not cause a Hand edited status. The Defaults form sets shared line wording, while a hand edit on one pipe stays on that pipe. Pipes with unreadable ends or ends on different grids are not assigned to this list and require drawing review.

No new OpenDCL control is needed. The LISP fills the existing `lvwCommand` and names its three columns when the palette opens. Reload `pf-load.lsp`, close and reopen `PFPALETTE` to see the combined list.

The other buttons repaint the palette afterwards. The trees come back with **nothing picked**, as in V5: `pfw:refresh` clears the picks first (a rebuilt tree makes them stale) and runs the whole fill inside one catch. Re-picking the last line was tried first; its read-back, outside the catch, stopped every open with `consp nil` (2026-11-03).

## The remembered list (2026-11-20)

The palette used to search the whole drawing on every click. A Run-tab line pick looked up the grid of every pipe in the drawing, and every lookup searched for anchors again. On a full drawing a canceled Defaults took a full minute.

Now the palette **reads the drawing once** (`pfw:read`) and keeps what it found in `*pfw-db*`:
- every line for the trees
- every line's Run list: structures, pipes and crossings, with their statuses

The list is held in memory only, one per drawing, and nothing is saved. A click answers from it. Each read prints `PFPALETTE: drawing read -- N lines, 0.42s`.

**The list is thrown away, never patched,** whenever the drawing changes:
- **The drawing-change reactor** (`pfw:db-watch`, a `vlr-acdb-reactor` tagged `PFSUITE-PALETTE`) empties it on any change: MOVE, grips, Properties, UNDO, anything. It then switches itself off until the next read, so a long command pays for it once. A reload of the suite keeps the one reactor; there are never two.
- **The palette's own buttons** empty it after their work (`pfw:db-forget`, in `pfw:act` and `pfw:reshow`). That doesn't depend on when AutoCAD runs the reactor.
- **Opening the palette** and the footer's Refresh read the drawing fresh.

The next click after a change reads the drawing again. Without the reactor, nothing is kept and every click reads.

**What stays live:** the `.cl` / `.pro` / `.tin` "NOT FOUND" checks on the Setup tab. A file can go missing without the drawing changing.

**The commands never use the list.** They write to the drawing, and a stale copy there would be saved into the drawing. They read the drawing themselves, with the same fast readers: `pfg:index` in pf-anchor, `pfr:all`'s name search, and `pfl:effname`.

**"needs refresh"** (Jake, 2026-11-20: "We need the refresh for any change that would need pfrefresh"). When a line is picked, each structure's profile copy, each pipe and each crossing on it gets PFREFRESH's own test: `pfu:copy-due-p`, `pfu:pipe-due-p` and `pfu:xing-due-p` in pf-refresh. These are the functions `pfu:run` itself calls, so the palette and Refresh Line can't disagree. Any block Refresh Line would rewrite shows **needs refresh**, whatever changed: rim, name, size, face, prefixes, a moved pipe, an invert or a crossing. "moved since Assign" still comes first. The answer is worked out on the line's first pick and remembered with the list. What it needs (the pipes and copies for the inverts, the grid tops) is read once per list.

**Defaults** reads the line's block types and pipes off the list (`pfw:dflt-line-catalog`), and refills the list only when edits were saved.

`pfw:lines`, `pfw:struct-rows` and `pfw:pipe-rows` stay fresh reads of the drawing, for PFSELFTEST. The palette shows `pfw:db`.

## The one change from V5

A button that changes the drawing has **Event Invoke = 1** ("Allow Command") in Studio, so its handler runs **as a command** and calls the work directly inside `pfd:run` — one undo group, the stage named on an error. V5 queued commands with `vla-SendCommand` and a ticket dispatcher; its first queued command of a session died at its own prompt (V5 OPEN-ISSUES). That channel is not ported.

Event Invoke's meaning comes from OpenDCL forum threads and the vendor's AUBlockTool sample (its palette button calls `getpoint` and `(command)` directly), not the reference page — the CAD test below settles it.

## Studio settings (Jake's)

| Control | Event Invoke | Events ticked |
|---|---|---|
| the form `pfsPalette` | — | Initialize |
| `tvwLines`, `tarLines` | 0 | SelChanged |
| `btnScan` `btnAnchor` `btnEdit` `btnNew` `btnRemove` `btnAssign` `btnStruct` `btnPipe` `btnRefreshLine` `btnRefreshAll` `btnEditStruct` `btnDefaults` `btnXing` | **1** | Clicked |
| the form `pfsDefaults` (modal) | — | Initialize; `btnSave` `btnCancel` Clicked |
| `btnZoom`, `btnIndex` | 0 or 1 | Clicked |
| `btnRefresh`, `btnHelp` (V5's footer, if kept) | 0 | Clicked |
| `lvwCommand` (single-select) | 0 | Clicked (a List View has no SelChanged) |
| `metaList` `lvwLinkage` `detailsList` | — | none |

`lblCounts`, if the form still has it, shows "N lines (M with grids)" — and,
after Crossings, "** N crossing(s) on <line> need a look".

### Added 2026-11-20 (you add it in Studio)

| (Name) | Type | Caption | Where | Event Invoke | Event |
|---|---|---|---|---|---|
| `btnXing` | Button | Crossings | Run tab, with the other line buttons | **1** | Clicked |

Generated handler: `c:pfsuite/pfsPalette/btnXing#OnClicked`. PFXLABEL on the
line picked; the line stays picked and its list refills.

**The Run list (`lvwCommand`)** now shows each crossing on the line —
`Crossing SAN. A  STA 1+00.00` (the crossing line and its station there) —
with its status: `PASS  22.4"`, `FAIL  15.6"`, `FAIL  wall unknown`, or `no
pipe on this line`. A FAIL is the palette's warning. A crossing row edits like a pipe (Edit
Attributes, then the line's refresh).

**New Structure** now refreshes the line after placing, so the new copies'
invert rows show straight away.

**The Defaults dialog** has a **Settings** group: plan label height
(PFASSIGN applies it), crossing clearance minimum, and the "draw the
dimension when within" margin — by line, utility or drawing.

## Rules (V5's, each paid for in CAD — `pfsuite-odcl\OPENDCL-WIRING.md`)

- Columns are added in **OnInitialize only** — AddColumns stacks.
- Data is filled **after** `dcl-Form-Show` — OnInitialize fires before the window exists.
- An undefined control symbol is nil and `dcl-*` on nil does nothing: caption and list writes are guarded.
- Never call a property the control type doesn't document — a missing one raises a modal no catch can stop.
- Tree selection handlers only **read**.
- A refused button always says why (`pfw:need`).
- `*pfw-filling*` is set while a tree is rebuilt: AddParent / AddChild fire SelChanged against a map not built yet.

## Not yet

- Line-limited reads for the commands: Assign builds the line tree over the whole drawing (it writes only the picked line); New Structure and Refresh Line read the drawing's structures to find the line's. The reads themselves are fast now (2026-11-20); limiting them to the line is still to do.
- The `pfsDefaults` modal form and `btnDefaults` still need to be added to the binary `.odcl` project in Studio. The LISP handlers and line-limited catalog are ready.
- The Tools tab; rims from the TIN (port step 5); keeping the picked line after the other buttons.

## Tests

PFSELFTEST group 12: the tree's rows (a gridded line, a line with no grid yet), the panels (datum, stations, the `.cl`, a stub's `.pro`, "(not set)"), and the refusals. Group 20 checks the fast reads and the remembered list:
- each fast read gives the same answer as the old way on this drawing
- the first click reads, the next answers from memory
- what it remembers equals a fresh read
- there is one reactor, never two
- after a change and an emptied list, the change shows

It prints how long the anchor read and the palette's whole-drawing read took. It also prints whether AutoCAD ran the reactor straight away (INFO, not a check). Group 7 covers Assign for one line. Group 13 covers the defaults the dialog saves and reads. The buttons and the Defaults form themselves are clicked by hand (FIRST-VERSION-TESTS §2).
