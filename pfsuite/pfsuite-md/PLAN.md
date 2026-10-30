# V6 — plan

*Rewritten 2026-10-16 to match decisions to date. V5 port inventory added 2026-10-22 (§11).*

V6 is a hard fork of V5. **Nothing in V5 is edited.**
- V5 keeps working, and stays the thing that runs on a live job until V6 replaces a command outright.
- The two are never loaded in the same session (Jake, 2026-09-08), so the `pf` prefixes are free.
- V6 lives at `LISP\PFSUITE\V6`.

## The thesis

> V5 stores files and re-derives facts. V6 stores facts and derives almost
> nothing at runtime.

V5 works well. What V6 fixes is the convoluted way V5 derived its data
(Jake, 2026-10-16), plus some upgraded functionality:
- Every expensive, fragile subsystem in V5 exists to reconstruct a fact that was never written down.
- V6 writes those facts down on the block, where the drafter can see and edit them.
- Geometry is demoted from *authority* to *proposer and auditor*.

**V5's look and behaviour carry over.** That covers text scaling, label layout,
the grid-top search, membership and numbering. For anything V5 already does,
the default is to port V5's version and change only what the block-based
design forces.

---

## 1. Workflow

This happens after the centerlines are designed and the blocks placed in
plan. It is palette-driven like V5, so each step is a button.

1. **Draw the grid** with existing and proposed ground. This is Carlson-driven and not written yet (`pf-grid`).
   - It places a `PFSUITE_ANCHOR` and writes the `.cl`, the surfaces and a copy stamp onto it.
   - Grid standards are still to discuss.
2. **Place the structures** (`PFSTRUCT`, "place structures in profile"). It places every structure **not placed yet**. Today that's every line in the drawing; once the palette exists, it's the line clicked there. The station line runs up to the labels at the grid top, and the label information is filled in. **Placed copies are PFREFRESH's from then on,** and the same goes for PFPIPE.
3. **Place the pipes** by hand (`PFPIPE` helps).
4. **Label the inverts and pipes.** The tool reads the pipe block. Not written yet.
5. Repeat for every utility.
6. **Label the crossings,** roughly as V5 does. Undecided, likely by pulling the invert labels from the block.
7. **Refresh** (`PFREFRESH`): relabels **only what changed**, not the whole drawing.
   - **How it tells:** each block carries a fingerprint of what it was built from.
   - **Hand edits are left alone:** typed text, moved labels, PFDEPTH, typed rim/name/face, pipe ends. A label reset by ATTSYNC is put back.
   - **It erases orphan and duplicate copies** (and names them), **but never places.**
   - **The split:** PFSTRUCT ("place structures in profile") places every structure not placed yet, and PFPIPE places pipes. **From then on, PFREFRESH carries everything.**

**Commands:** one place command per block type, plus one refresh.
- `PFSTRUCT` places **every structure type**.
- `PFPIPE` places pipes.
- `pf-grid` will draw the grid and place the anchor.

No step depends on a later one. In particular, **placing structures never needs pipes.**

---

## 2. The data model

### 2.1 Blocks

Every block is named `PFSUITE_<NAME>` (Jake, 2026-10-15). Names are matched
**exactly**, or as the name plus a number size (`PFSUITE_DBI_04`), **never by
prefix**.

| Block | What it is |
|---|---|
| `PFSUITE_CBI` | **One** lookup-driven block for all sizes (not one per size). States: PLAN + nine faces |
| `PFSUITE_CBI_BOX`, `_DBI`, `_SMH`, `_DMH`, `_MH`, `_HDWL` | to come. PLAN + PROFILE |
| `PFSUITE_PIPE` | the profile pipe. States `WALL OFF` / `WALL ON` |
| `PFSUITE_ANCHOR` | the grid anchor. V5's `PF-ANCHOR` / `PF-GRIDANCHOR` are still read |

**The same structure block serves plan and profile.**
- A plan insert (the "alpha block") sits in the `PLAN` state.
- A profile copy sits in the state named by its face code.
- `PFVIEW` says which, so no visibility state has to be read.

**Scale.** Profiles are true size horizontally (1 unit = 1 station foot) and
×10 vertically on every current grid (20/2, 40/4, 50/5). So widths are drawn
true size, and heights at ×10. A grid with a different exaggeration would need
the block scaled.

### 2.2 The face matrix — `PFFACE`

Two letters: the face the line **enters** through, then the face it **leaves**
through. `B` back, `F` front, `S` side.
- At zero rotation a CBI's front faces **+X**.
- The line's direction is sampled 5 ft either side of the structure.
- Within 45° of front is `F`, within 45° of back is `B`, otherwise `S`.
- Within 5° of a 45° corner is reported, not silently resolved.

Today `PFFACE` is **one attribute on the alpha block**. Two cases are still
open (§9):
- a junction, whose copies on different lines may need different faces;
- a structure at the very end of a line, which gets no face. For now, type one by hand.

### 2.3 Attributes — 25 tags

Every structure definition carries the same set.

- **The record** (hidden): `PFNAME` `PFTYPE` `PFSIZE` `PFPOS` `PFRIM` `PFSTRUCT` `PFINLET` `PFVIEW` `PFFACE`
- **The label stack** (visible, at the grid top): `PFSTA1` `PFSTA2` `PFSTA3` `PFCON` `PFTEXT2` `PFELEV`
- **The invert fan** (visible): `PFINV1` … `PFINV5`. Written by the invert step later, not by PFSTRUCT.
- **Drafter inputs** (hidden): `PFSTAPRE` `PFSTASUF` `PFCONPRE` `PFCONSUF` `PFELEVSUF`. Typed on any block and pushed to every structure. `PFCONSUF` is no longer used.

**Label standard** (Jake, 2026-10-16):

```
STA. 4+09.69 STORM LINE 'BA' =      grid's own line first, then others A-Z
STA. 3+00.00 STORM LINE 'BC'        " =" on every station row but the last
CONST. DRAINAGE MH BA-5/BC-1        prefix + type words + PFNAME; no size
W/ CURB INLET CASTING
G.L. 758.25                         rim from PFRIM
```

- **The station suffix** defaults to `[util] LINE '[line]'`, filled in from the `.cl` name split at the **first** underscore, as V5 does (`Storm_BA` gives `STORM` and `BA`).
- **The wording is a default.** Drafters type over any row that should differ, and the tool keeps it.
- **`PFNAME`** will be **built by the tool** from V5's line tree (`BA-5/BC-1`), and the drafter may edit it. Until then it's typed.

### 2.4 Stored data (XDATA, tool only)

| Key | Meaning |
|---|---|
| `MEMB` | `((line station offset) …)`: every line the structure is on |
| `SRC` | `((tag source last-written-value) …)`: what the tool last wrote, per tag |
| `SCHEMA` | record version |
| `PLAN` / `LINE` | profile copies only: the alpha block's handle, and which line |
| `POS` | where the tool last put a label |
| `SEEN` | a fingerprint of what the block was last built from. PFREFRESH compares it |

- **Values are chunked** under the 255-byte limit.
- **`SRC` is what catches a hand edit.** If an attribute no longer holds what the tool wrote, a person changed it. It is marked hand-typed (asserted) and never overwritten.
- **Membership lives on the structure, not the line.** This is V5's own conclusion (`INDEX-DESIGN.md`). A structure with two entries is a junction.

### 2.5 Dynamic parameters

AutoCAD allows only **one visibility parameter** per block, but any number of
other parameters.

**PFSUITE_CBI**

| Name | What it does |
|---|---|
| `PFVIS` | the states |
| `PFSIZE_LU` | the size lookup (4–12). Drives `PFOD_R`, `PFID_R`, `PFSLAB` and `PFBARREL_R`. PFSTRUCT copies it from the alpha block |
| `PFBARREL_R` | the barrel half-width: two Stretch actions, the left one at 180° offset, as a lookup column. Width = size |
| `PFTOP` | the station line's top. **Fitted by the tool** to the end of the first label row |
| `PFDEPTH` | the barrel bottom. **Set by the drafter** with the grip. The tool never touches it |

**PFSUITE_PIPE**

**Its label is two rows** (Jake, 2026-10-16). Two rows because they may need
moving or stacking on a short pipe:

```
PFLABEL   CONST. 45 L.F. ~ 15"        PFLENPRE length PFLENSUF size
PFLABEL2  ADS N-12 HDPE @ 5.5%        material PFSLOPEPRE slope PFSLOPESUF
```

- **Rounding:** whole feet, slope to 0.1%.
- **Placement:** the rows run along the pipe, straddling its centre 2.0 text heights apart, as V5 did.
- **Shared inputs:** the four are **shared across every pipe**, with the same logic as the structure inputs (`pfr:sync-inputs`).

**The leader** (Jake, 2026-10-22) is **drawn by the tool**, not held in the
block. A leader built into the block was tried first and dropped: its rotate,
stretch and scale actions dragged each other's points around. The drafter
only drags the label's grip, `PFLEAD`; the tool does the rest.

- **What it is:** one polyline per pipe, on the pipe's layer. Its first segment tapers from nothing at the tip to the arrow's width, and that is the arrowhead. It carries the pipe's handle (XDATA `PIPE`).
- **Kept in step by PFREFRESH:** redrawn whenever the pipe, the label or the leader itself changed; erased when the label goes back inside, or when its pipe is gone. A leader edited by hand is redrawn.

- **Label inside the pipe:** rotated to the pipe, no leader. Where the tool puts it unless dragged.
- **Label dragged outside:** stays where it was dragged, turned level, on a leader.
  - **Arrow:** on the pipe's top when the label is above it, its bottom when below, at the pipe's midpoint. Outside the wall when the walls show.
  - **Shape:** a sloped leg from the arrow to a bend, then a level landing toward the text.
  - **Landing end:** 1 unit (at 1"=20') short of the top row's insertion point. The rows are middle-left when the label is right of the arrow, middle-right when left.
  - **Arrowhead:** 1/8" plotted, so 2.5 at 1"=20'. Every leader size scales with the text.
- **Dragged back inside:** rotated to the pipe again, leader off.
- **PFREFRESH** redoes rotation, justification, state and leader every time. It never moves a dragged label.

| Name | What it does |
|---|---|
| `PFRUN X/Y` | point parameter for the downstream end |
| `PFDIA` | the inside diameter |
| `PFWT`, `PFWB` | wall top and bottom |
| `PFVIS` | `WALL OFF` / `WALL ON` |
| `PFLEAD` | point: the label's grip. Moves both rows. Rides the `PFRUN` ×0.5 move |

**Text** is set per copy, never frozen in the block. Height = 1.60 × (horizontal
plot scale ÷ 20), as in V5. Every spacing is a multiple of the text height.
Vertical exaggeration never affects text.

### 2.6 Block rules, learned the hard way

- **Never nest a dynamic block inside a `PFSUITE_*` block.** Nested **plain** geometry is fine, but it can't be stretched.
- **Stretch, not Scale,** for widths. A Stretch moves only the line ends inside its frame. It must follow the parameter point that moves.
- **BSAVE saves into the open drawing only.** Save the library drawing before redefining the block elsewhere, or the old copy wins.
- **ATTSYNC keeps values and stored data, and resets label positions.** CBI, anchor and pipe all passed `PFSYNCTEST` on 2026-10-15.
  - Rerun `PFSYNCTEST` after any block change.
  - PFREFRESH puts CBI and pipe labels back. A dragged pipe label stays put, because its spot is read from the `PFLEAD` grip, which ATTSYNC leaves alone.
- **Hatches in a dynamic block must be Associative = Yes** (Properties). That is what made the pipe walls and the arrowhead follow their actions (2026-10-22).

---

## 3. Elevation derivation (later)

Rims are typed by hand on the alpha block for now. A TIN is offered if the
anchor names one. The planned rules are unchanged:

| `PFPOS` | Rule | Source |
|---|---|---|
| `ONGRADE` | road profile at the station, less cross-slope × distance out | `CL` |
| `SAG` | as ONGRADE, snapped to the low point. Warns if not at one | `CL` |
| `SURFACE` | surface TIN at the structure's plan point | `TIN` |

1. Every elevation carries where it came from. `NONE` means *not on record*, never zero.
2. Tool values can be recomputed. Hand-typed values are sticky.
3. Engineering judgement is a hand-typed value, not a fudge.

---

## 4. Carlson

Confirmed in CAD (`PF6PROBE`, 2026-09-03):

| What | Finding |
|---|---|
| `cl_location_at_pt` | the offset is **signed**: negative left, positive right |
| `cf:dtm_api` | `load_tin` / `tin_z` / `unload_tin` work |
| metric flag | **`IS_METRIC`**, not `ACMETRIC` |
| `swrStruct.dta`, `inlet.dta` | plain text under `usrdir$` |
| `pipesize.dta` | **round pipe only**: the first field is the shape, `0` = round. The wall thickness is the last field |
| `pipen.dta` | the materials |

- **`pf-carlson` is the only file that may name `cf:road_api` or `cf:dtm_api`.**
- **Trap:** a failed location request prints to the command line from below LISP, where it can't be stopped. Anything asking about many structures needs **V5's corridor pre-filter**, which reads the `.cl` file itself first.

---

## 5. What carries over from V5

- **Text scaling and label layout:**
  - row 1 left of the station line, the rest to its right, reading up;
  - 1.0× and 1.5× text height offsets.
- **The grid-top search:** the highest `PF-GRID-MJR` line above the station, per station. When there is none, PFSTRUCT says so and puts the labels 10 text heights above the structure.
- **Membership:**
  - on a line means within **0.15 ft** of the centerline and inside its station range, ±0.01 ft;
  - same-utility lines only. A different utility meeting it is a crossing.
- **The line tree** (ported 2026-10-22, in pf-index; PFASSIGN writes the names, 2026-10-27):
  - the lines are every line: anchors, plus V5's grid-less "stubs" in the drawing dictionary. A name uses only lines of the structure's own utility;
  - each structure is numbered along each line, with the **lowest station = 1**;
  - the name is the lines A to Z as `LINE-number`, joined by "/";
  - **with the bend fix:** where a structure is on a line is measured against the read `.cl` (V5's `pf:cl-parse`), not asked of Carlson. Carlson answers nothing just past a bend, and V5 dropped those structures silently, its one critical open bug;
  - **headwalls count** (V5 is right). Until `PFSUITE_HDWL` exists, `*pf-count-only*` (`HDWL`, `HDWL_<size>`) takes its number but is never named or assigned.
- **The plan side and the profile side** (Jake, 2026-10-27): **PFASSIGN** does the plan -- no pick, every plan structure on every line by membership: names, lines and stations, face, rim from the TINs on a Yes. **PFREFRESH** does the profile only, and says "run PFASSIGN first" for a plan structure moved or new since. The run: PFASSIGN, PFSTRUCT, PFREFRESH.
- **Inverts** (later): fan base at the lowest invert − 4.0 × text height, column gap 2.0 ×, and a first-structure shift measured flat on the sheet.
- **Pipe labels** (later): offset 3.2 × sf, two rows straddling the pipe centre.
- **Crossings** (later): V5's discovery, with the label kept inside the block.

**Dropped from V5:**
- the re-derived membership and label-identity machinery;
- the rim scan;
- pfqty's forked gather (the exports themselves are "decide later", §11);
- the loose text stacks;
- the 13 palette diagnostic commands.

---

## 6. Module layout

V5's structure: one folder per module, a README beside each, and an
**enforced load order**. A module may only call modules loaded above it.

| Load | Module | Prefix | Holds |
|---|---|---|---|
| 1 | pf-cfg | | constants and **the name contract** |
| 2 | pf-lib | `pfl:` | **the shared engine, read-only:** maths, formatting, messages, strings, files, real block names, reading dynamic properties and block geometry |
| 3 | pf-carlson | `pfc:` | every Carlson API call |
| 4 | pf-files | `pff:` | where file dialogs open |
| 5 | pf-record | `pfr:` | the only reader and writer of attribute values and stored data |
| 6 | pf-anchor | `pfg:` | reads the grids. Never writes |
| 7 | pf-index | `pfm:` | which lines a structure is on, read off the `.cl` file; V5's line tree, numbers and names |
| 8 | pf-draw | `pfd:` | **the only writer of entities and parameters, no commands,** plus `pfd:run`, the one command wrapper (one UNDO, error names its stage) |
| 9 | pf-assign | `pfa:` | `PFASSIGN`: the plan side, drawing-wide, no pick -- names, lines, face, rims (Jake, 2026-10-27) |
| 10 | pf-struct | `pfs:` | `PFSTRUCT` (was PFDRAW) |
| 11 | pf-pipe | `pfp:` | `PFPIPE`, Carlson pipe libraries, pipe labels |
| 12 | pf-refresh | `pfu:` | `PFREFRESH`: the one refresh, profile side, changed blocks only |
| reserved | pf-grid | | the grid and anchor command |
| last | pf-bench | `pfb:` | the workbench. **Not part of the suite** |

**Shared code is called, never copied.** If two modules need a helper, it
moves to pf-lib (reads) or pf-draw (writes).

**The name contract.** Block, state, tag and parameter names are typed in the
Block Editor *and* written in `pf-cfg`, with no compiler between them.
- No other file contains those strings.
- Once a drawing carries a name, changing it is a schema bump.
- `PFGATE` checks that the two halves agree.

**The workbench** is deleted whole when V6 ships. Its commands: `PFMKATT`
`PFSEL` `PFGATE` `PFSWAP` `PFRECTEST` `PFSYNCTEST` `PFPIPETEST` `PFGRIDTEST`.

---

## 7. Status (2026-10-22)

**Working in CAD** — Jake ran all of `FIRST-VERSION-TESTS.md` A–F on 2026-10-22: "everything looks good".
- **PFSUITE_CBI:** all tags, parameters and states. PFTOP and PFDEPTH both move the right end. The barrel width follows the size.
- **PFSUITE_PIPE:** the two-row label with shared inputs; the label grip (PFLEAD) and the tool-drawn leader.
- **Anchors:** 67 grids read, copy check fixed, the `.cl` read from V5's stored records.
- **ATTSYNC:** loses nothing on the CBI, anchor or pipe.
- **PFSTRUCT, PFPIPE, PFREFRESH,** the module refactor, the label standard.

**Written, not yet seen in CAD**
- **The line tree** (2026-10-22): numbers and names, written by PFREFRESH; the bend fix; `PFLINETEST`. Tests: section G of `FIRST-VERSION-TESTS.md`.

**Next** — the V5 port order agreed 2026-10-22 (§11):
1. The line tree, checked in CAD against V5's names on the same drawing.
2. PFSETUP, the anchor checks and PFREMOVE.
3. The palette.
4. Inverts (workflow step 4).
5. Rims (V5's PFGL → the ONGRADE rule, §3).
6. Crossings, and PFPRO.
7. Exports, if any.

`pf-grid` (drawing the grid) waits on the grid standards discussion. The
remaining structure types come in alongside.

---

## 8. Not decided yet / later

- **Layers** for profile copies and labels. V5 used PF-ANNO (green, no-plot).
- **Text style** is set in the block by Jake. The code doesn't set one.
- **Pipe wall hatching** that follows the stretches. Not worked out.
- **Prefix and suffix scope.** Today a change on any block goes to every structure, with no per-profile override. Revisit later.

---

## 9. Open questions

1. **How is a road `.cl` told apart from a utility one?** ONGRADE and SAG depend on it.
2. **Superelevated curves:** cross-slope is not one number there.
3. **Grate depression:** which types, and one number or per type.
4. **The inlet family** for `PFINLET`: does `PFTYPE` alone settle it?
5. **Faces at a junction and at a line's end.** Today there is one PFFACE per structure, and none at a line's end.
6. **Junction depth:** each profile copy has its own PFDEPTH grip, so one structure could show different depths on different sheets.
7. **Crossing blocks:** one parametric block or per size, and whether the label can live inside it.
8. **Material wall thicknesses** for outside-to-outside clearance. `pipesize.dta` holds one per size.
9. **Are three station rows enough?** That's a junction on three lines.
10. **PFSIZE shows blank** on some CBIs. Cosmetic now, since PFSTRUCT reads the lookup, but the field needs checking.

---

## 10. Non-goals

- No migration path from V5 records. V5's anchors and stubs are **read**, never converted.
- No metric support beyond a guard that refuses.
- No second UI surface: the palette and the one run dialog, nothing else.

(The `.stm` export was listed here. Exports are now "decide later", §11.)

---

## 11. The V5 port (agreed 2026-10-22)

A pass through every V5 module, its README, its command list, its open
issues and `Version 5.1.md`. **V5 is ported mostly as-is;** only what the
block-based design forces changes.

### Needed for the workflow now

| V5 | What it does | V6 |
|---|---|---|
| **Line tree** (`pftools-lib` §1–3, `pfanchor` §4b–4c) | `.cl` reading, corridor and box tests, stubs, the line list, membership, numbering, names | **Ported** into pf-index, **with the bend fix.** V5's speed caches left out; V6's MEMB kept |
| **PFSETUP** (+ `pfdialog.dcl` `pfsetup_main`) | Scans the sheet's `PF-NAME` text and registers stubs with their `.pro`; Anchor / Edit / New: the record dialog, two corner picks, writes the anchor | Port into a new `pf-setup`. Writes `PFSUITE_ANCHOR` with the CL attribute. Drops V5's labelling STATUS records |
| **Anchor checks** (`corner-check`, `probe-corner`, `xform-moved-p`) | Warns when an anchor no longer matches its grid (V5's own open issue) | With PFSETUP; reported by PFREFRESH |
| **PFREMOVE** | Removes a line's anchor | **Only the anchor is deleted** (Jake): the line just leaves the line table. Nothing else is erased |
| **PFADOPT** | Adopts anchors pasted from another drawing | Later; small |
| **Palette** (`pfpalette.lsp`, `pfsuite.odcl`) | Registry and Commands tabs, the deferred-command channel | `pfp:` → `pfw:`. Fix V5's open bug first: the session's first deferred command dies at its own prompt |

### When that workflow step comes

| V5 | Step | V6 |
|---|---|---|
| **PFINVERT** | Inverts | Its layout rules (fan, gap, column order by role, first-structure shift, one stack per shared structure). Data from the **pipe blocks' ends**, rows into the CBI's `PFINV1–5` |
| **PFXLABEL + PFXALL** | Crossings | Discovery as-is (`.cl` × `.cl`, rejecting shared structures, line ends, and hits outside the `.pro`); one `X_` record per anchor. How a crossing is drawn: §9 Q7 |
| **PFPRO** | Feeds crossings and exports | **Writes `_INV.pro` from the pipe blocks** (Jake), not from a drawn polyline |
| **PFGL** (`Diagnostic_Tools`) | Rims | Its gutter-elevation engine becomes §3's ONGRADE rule |

### Decide later (Jake)

PFREPORT (Hydraflow `.stm`), PF2SEW (Carlson `.SEW`), PFQTY (takeoff). The
blocks now carry size, material, rim and inverts, so each is simpler than in V5.

### Small pieces

- Into pf-bench, cut down: `PFBAD` (how the scan reads each `PF-NAME` text), `PFDUMP`, `PFSYS`, `PFPAPI`, `PFPDIAG`.
- A metric guard that refuses (`IS_METRIC`).
- A backtick line name (`` STORM LINE `DA` ``) reported, not silently skipped.

### Not coming over — V6 replaced it

| V5 | V6 instead |
|---|---|
| PFLABEL text stacks, PFLABELSET, the settings file | PFSTRUCT, block attributes, shared inputs |
| Pass records, STATUS, labelled/outstanding checks, drift echo | Fingerprints and PFREFRESH |
| PF-ANNO layer logic, erasing by stored handle | Blocks; layers later |
| PFINDEX and its caches | MEMB on the structure, kept current by PFREFRESH |
| The zoom parade | Dropped in V5 too |
