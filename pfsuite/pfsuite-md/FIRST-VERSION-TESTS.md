# V6 first version — tests

CBI + PIPE only. The point is to find out whether the data holds up and
how drafters get on with the blocks. Write down what happened for each one,
including "it worked".

**First, every time: PFSELFTEST** (2026-10-27). It runs the checks that
don't need your eyes -- label rows, prefixes, the pipe label, refresh scope,
line-tree names -- on test blocks it makes and erases, and prints PASS / FAIL.
Paste its result. The rows below are for what it can't see.

**Set up:** open `V6_Test.dwg`, APPLOAD `pfsuite\pf-load.lsp`. Do **not**
also load the old `pfpipe.lsp` from the V6 folder. The suite has its own
PFPIPE now.

## Before you start (once)

1. **Current blocks.** `V6_Test.dwg` was last saved 9/25. The pipe block
   was rebuilt 10/2 (`PFSUITE_BLOCKS.dwg`). If the test drawing has an
   older pipe block or PFSUITE_CBI, bring the new ones in first. The pipe
   block is now `PFSUITE_PIPE` (the command is still PFPIPE). Grids can
   carry `PFSUITE_ANCHOR` or V5's `PF-ANCHOR`; V6 reads both.
2. **PFGATE on a pipe.** Insert one PFSUITE_PIPE anywhere, run PFGATE, and pick
   it. You want "ready to test". Then **erase it**, along with any other
   leftover test pipes.
3. **PFGATE on a plan CBI.** You want "ready to test". It checks the tags,
   PFSIZE_LU / PFTOP / PFDEPTH and the ten states. It also tries the first
   two items in section C below, then puts everything back.
4. **Plan CBIs** are `PFSUITE_CBI` inserts, in the PLAN state, with their
   size picked, sitting on the storm line (within 0.15').
5. **A CBI at the very start or end of the line** gets no face, because
   there's no line on one side to read it from. Its profile copy would stay
   in the PLAN state. For now, type a PFFACE on it by hand (e.g. `FF`)
   before PFSTRUCT.

---

## A. Does it work at all

1. **PFGRIDTEST.** Click inside a grid, then click a few grid lines. The
   stations and elevations it prints should match the grid's own labels.
2. **PFASSIGN.** No pick, no selection (2026-10-27). It asks once whether to
   read rims from the grids' TINs, then names every plan CBI and lists each
   with its line(s), station(s) and face. A junction lists all its lines.
3. Type a rim on each plan CBI in Properties (PFRIM) if you said No.
   Names come from PFASSIGN.
4. **PFSTRUCT.** No pick -- it does the whole drawing. You should get one
   CBI per plan CBI, on the grid that shows its station, at its station and
   rim, with the station / CONST. / G.L. rows at the grid top. The output is
   grouped by grid. PFSTRUCT does structures only -- it never reads or
   changes pipes.
5. **PFSTRUCT** again. "0 placed, N already placed" -- nothing changes,
   nothing doubled. Already-placed copies are PFREFRESH's from here on.
6. **Set a barrel depth** with the PFDEPTH grip, then PFREFRESH. The barrel
   is left exactly where you put it.
7. **PFPIPE.** Click the upstream invert, then the downstream invert, near
   two CBIs. Two label rows along the pipe, straddling its centre:
   `CONST. 45 L.F. ~ 15"` over `ADS N-12 HDPE @ 5.5%` -- whole feet,
   slope to 0.1%. (Needs PFMKPIPEATT run on the block first, then ATTSYNC.)
   Then change PFLENPRE on that pipe (e.g. `INSTALL`) and place a second
   pipe: both should now read `INSTALL`.
8. **PFREFRESH.** The CBIs are unchanged and the pipe is untouched.

## B. Drafters doing normal things

PFASSIGN does the plan, PFSTRUCT and PFPIPE place, PFREFRESH carries the
profile after. Run PFREFRESH after each one (PFASSIGN first where it says)
and write down what it says.

| # | Do this | Expect |
|---|---|---|
| 1 | Type over a CBI label row | Kept, and PFREFRESH says so |
| 2 | Change a rim on the PLAN CBI | Profile CBI moves to the new rim, G.L. row updates (the barrel moves with it) |
| 3 | Move a plan CBI along the line, PFREFRESH only | "moved or new since PFASSIGN -- run PFASSIGN first", naming it; its copy does not move |
| 3a | Then PFASSIGN, then PFREFRESH | Re-stationed (and renumbered if it passed another), profile CBI moves |
| 4 | Move a plan CBI well off the line, PFASSIGN, PFREFRESH | PFASSIGN: "left STORM_.. -- on no line now"; PFREFRESH: profile CBI erased and named |
| 5 | Erase a plan CBI | Its profile CBI is erased and named |
| 6 | COPY a profile CBI | The copy is erased as a duplicate |
| 7 | COPY a plan CBI | "Two alpha blocks are named …" warning (from PFSTRUCT) |
| 8 | Change PFSTAPRE on one CBI (e.g. `STA:`) | Every CBI's station row changes |
| 9 | Type two different PFSTAPRE values on two CBIs | Reported, neither applied |
| 10 | Change a plan CBI's size | Profile CBI changes size |
| 11 | Draw a pipe uphill with PFPIPE (low end first) | "runs UPHILL" warning when placed |
| 12 | UNDO once after a PFREFRESH | The whole run goes back |
| 13 | Save, close, reopen, PFREFRESH | "0 updated" -- nothing changes |
| 14 | Copy a CBI into another drawing, PFSTRUCT then PFREFRESH there | Anything odd? |
| 15 | New plan CBI on a line, PFASSIGN, then PFSTRUCT | PFASSIGN lists only the new one (and any renumbered); only the new one is placed |
| 16 | PFASSIGN twice in a row | The second run: "0 assigned, 0 updated", no name lines |
| 17 | (2026-10-27) Reload, PFREFRESH Drawing, before touching the block | "[CBI] PFCONPRE updated to the new default"; "CBI blocks have no PFELEVPRE -- using G.L."; rows read `CONST. CURB BOX INLET BA-5/BC-1` and `G.L. 758.25` |
| 18 | BEDIT PFSUITE_CBI, PFMKATT (adds only PFELEVPRE), BSAVE, ATTSYNC, PFREFRESH Drawing | The "no PFELEVPRE" line is gone; rows unchanged |
| 19 | Type `T.C.` in PFELEVPRE on one CBI, PFREFRESH | Every CBI's elevation row reads `T.C. ...` |
| 20 | Blank PFELEVPRE on one CBI, PFREFRESH | Every CBI's elevation row disappears |
| 21 | Type `CONST. 4' DRAINAGE MH` in PFCONPRE, PFREFRESH | Every CBI reads `CONST. 4' DRAINAGE MH <name>` -- no `CURB BOX INLET` added |

ATTSYNC is safe on these blocks (section D); run PFREFRESH after it.

**Later, with the pipe work:** invert rows on the CBIs, and which pipe end
belongs to which CBI.

## C. Things nobody has seen work yet

These are the guesses most likely to be wrong. If one fails, say which.

- **PFTOP.** PFSTRUCT measures the station line's top inside the block,
  sets PFTOP, and measures again. "Did not move …" means the stretch
  action doesn't catch that end. (PFDEPTH is yours; PFSTRUCT never sets it.)
- **Moving the label attributes.** They are LockPosition = Yes in the block.
  PFGATE's dry run moved one by code and it held through a REGEN; PFSTRUCT is
  the first real use.
- **Text height.** 1.60 × (horizontal scale ÷ 20), the same as V5.

## D. ATTSYNC check (repeat now and then)

On a **copy** of a drawing:
1. **PFSYNCTEST.** It snapshots every CBI, pipe and anchor and changes nothing.
2. **ATTSYNC** the block(s) you want to test.
3. **PFSYNCTEST** again. Every FAIL line names the block and what was lost.
4. **PFREFRESH** to put the labels back (ATTSYNC resets their positions).

Do this after any change to a block definition, and paste the result.

## E. PFREFRESH

The first run on an existing drawing updates everything once (nothing has
a fingerprint yet). Run it once, then:

| # | Do this, then PFREFRESH | Expect |
|---|---|---|
| 1 | Nothing | "0 updated", everything unchanged and left alone |
| 2 | Change a rim on an alpha block | Only that structure's profile copies updated |
| 3 | Move an alpha block along its line, PFASSIGN, then PFREFRESH | Re-stationed by PFASSIGN, its copy moved by PFREFRESH |
| 4 | Type over a CBI label row | That copy "updated", the row kept as typed |
| 5 | Drag a CBI label row somewhere | Row left where you put it |
| 6 | Drag a PFDEPTH grip | Barrel left exactly as you set it |
| 7 | Grip-stretch a pipe's downstream end | That pipe's L= and slope update, nothing else |
| 8 | Change a pipe's PFSIZE | Diameter and row 1 follow |
| 9 | Change PFLENPRE on one pipe | Every pipe's row 1 follows |
| 10 | ATTSYNC PFSUITE_CBI | Labels go back against the station line |
| 11 | Erase an alpha block | Its profile copy erased, and named |
| 12 | A new alpha block on a line, PFASSIGN | Listed as not placed -- "run PFSTRUCT" (refresh never places) |
| 13 | UNDO once | The whole refresh goes back |

**Scope** (2026-10-27). PFREFRESH asks `Refresh [Selected/Line/Drawing] <Line>`.
Every run ends with a `Time:` line -- paste it each time.

| # | Do this | Expect |
|---|---|---|
| 14 | PFREFRESH, Enter (Line), click a CBI copy on STORM_BA | Header says "line STORM_BA"; only BA's copies and pipes are checked |
| 15 | Line, click a plan junction (BA-5/BC-1) | Both lines, STORM_BA and STORM_BC |
| 16 | Line, click a pipe, then its leader, then an empty spot in a grid | Each finds that grid's line |
| 17 | Selected, pick two copies and a pipe | "3 block(s) checked" |
| 18 | Drawing | Everything, as before. Compare its `Time:` with a Line run |
| 19 | Erase a pipe on BA, then Line on another line | BA's leader is NOT erased; Line on BA erases it |

## F. Pipe label leader (2026-10-22)

The leader is **drawn by the tool** (a polyline), not part of the block.

**First, in the block:** take the leader out of PFSUITE_PIPE -- the leader
lines, the arrowhead, PFTIP, PFBEND, PFTAIL, PFARROW, PFASZ and the two
LEADER states. **Keep PFLEAD** and its Move of PFLABEL / PFLABEL2. BSAVE,
redefine it in the test drawing, then run **PFGATE** on a pipe: you want the
label grip present and the two states WALL OFF / WALL ON. The first
PFREFRESH after loading updates every pipe once (the fingerprint version
went up).

| # | Do this, then PFREFRESH | Expect |
|---|---|---|
| 1 | Nothing (a pipe never dragged) | Label along the pipe, centred, no leader. The PFLEAD grip sits between the two rows |
| 2 | Drag PFLEAD **below** the pipe, to the **right** of its middle (what went wrong last time) | Label level, left-justified. Leader: arrow on the pipe's bottom at its middle, a sloped leg down to a bend, a level landing ending 1 unit (at 20 scale) short of the top row |
| 3 | Drag it **below, left** of the middle | Same, but right-justified, the landing coming in from the right |
| 4 | Drag it **above** the pipe | Arrow on the pipe's top instead |
| 5 | Turn the pipe's walls on (state WALL ON), then PFREFRESH | Arrow on the outside of the wall |
| 6 | Measure the arrowhead with DIST, and look at it | 2.5 long at 20 scale (5.0 at 40), filled, pointing at the pipe |
| 7 | PFREFRESH again | "0 updated" -- the dragged label stays, nothing moves |
| 8 | Grip-stretch the pipe's downstream end | Label shifts with the pipe's middle (PFLEAD rides the stretch), still level; leader redrawn to the new middle |
| 9 | Erase the leader by hand | Drawn again |
| 10 | Erase the pipe | Its leader erased and counted |
| 11 | ATTSYNC PFSUITE_PIPE | Label goes back to the dragged spot, level, on its leader |
| 12 | Drag PFLEAD back inside the pipe, anywhere | Label back at the pipe's centre, along it; leader gone |
| 12a | Never dragged out: drag PFLEAD a little along the pipe, still inside | Back to the centre |
| 13 | UNDO once | The whole refresh goes back |

## G. Line tree and names (2026-10-22)

V5's line tree: every structure numbered along every line it is on (lowest
station = 1), its name built from that (`BA-5/BC-1`), and PFASSIGN writing
it (2026-10-27 -- was PFREFRESH). Where a structure sits on a line is now read off the `.cl` file, not
asked of Carlson -- **the bend fix** for V5's dropped structures.

**Use a drawing V5 has labelled**, so the names can be compared.

| # | Do this | Expect |
|---|---|---|
| 1 | APPLOAD `pf-load.lsp`, then **PFLINETEST** | Every line listed: grid or stub, `read` (or `WALKED`, with a note saying why), its station range. No Carlson "unable to locate point" errors on the command line |
| 2 | Compare PFLINETEST's names with V5's labels on the same lines | They match. Headwalls show as `(n)  HDWL_.. (not ours)` and take their number (STORM_AA should read AA-2, AA-3). A difference where V5 counted another structure block not yet replaced is expected -- note which |
| 3 | A structure just past a bend in a line (V5's line DF case, if it's in this drawing) | Listed on its line with a sensible station -- not missing |
| 4 | Read "Near a line but NOT on it" | Each one is a structure 0.15'–1.0' off a line. Is it really off, or is the tolerance wrong for it? |
| 5 | **PFASSIGN** | Names written ("named BA-5" / "BA-4 -> BA-5"); each structure listed with its line(s) and station(s) as PFLINETEST shows them, to the hundredth |
| 6 | PFSTRUCT, then PFREFRESH | Each placed copy's CONST row shows its name |
| 7 | PFASSIGN again | "0 assigned, 0 updated", no name lines -- nothing changed |
| 8 | Type a different PFNAME on one alpha block, PFASSIGN, PFREFRESH | "typed by hand -- kept"; your name stays, and its copies show it |
| 9 | Copy a plan CBI to a new spot on a line (between two others), PFASSIGN, PFREFRESH | Everything after it on that line renumbers by one; their copies follow |
| 10 | A junction (e.g. BA-5/BC-1) | PFASSIGN lists both lines in one line; PFSTRUCT places a copy on both grids |
| 11 | UNDO once after PFASSIGN | The names and lines go back too |
| 12 | PFLINETEST's "On no line" | Each with its X,Y and nearest line -- go and look |
| 13 | PFLINETEST's "Stacked" (the STORM_AA pairs, before you erase them) | Both pairs listed; PFASSIGN says the same |
