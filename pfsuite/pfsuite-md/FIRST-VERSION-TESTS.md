# V6 first version — tests

CBI + PIPE only. The point is to find out whether the data holds up and
how drafters get on with the blocks.

**PFSELFTEST does the testing** (Jake, 2026-10-30: "I want PFSELFTEST to do
all of the testing"). It builds its own test lines, grids, structures and
pipes far out in model space, runs each command's real work on them, prints
PASS / FAIL with what it got, and erases everything it made. Your real
blocks are only read. What's left below is what code can't do: the dialog,
the clicks, UNDO, another drawing, and looking at your real drawing.

**Set up:** open `V6_Test.dwg`, APPLOAD `pfsuite\pf-load.lsp`. Do **not**
also load the old `pfpipe.lsp` from the V6 folder. The suite has its own
PFPIPE now.

## Before you start (once)

1. **Current blocks.** The pipe block is `PFSUITE_PIPE` (rebuilt 10/2,
   `PFSUITE_BLOCKS.dwg`). If the test drawing has an older pipe block or
   PFSUITE_CBI, bring the new ones in first. Grids can carry
   `PFSUITE_ANCHOR` or V5's `PF-ANCHOR`; V6 reads both.
2. **The blocks' attributes.** PFSELFTEST says which are missing:
   - PFSUITE_CBI without PFELEVPRE: BEDIT, **PFMKATT**, BSAVE, ATTSYNC.
   - PFSUITE_PIPE without PFLABEL2 or the four label inputs: BEDIT, **PFMKPIPEATT**, BSAVE, ATTSYNC.
   - PFSUITE_ANCHOR without all nine tags: BEDIT, **PFMKANCATT**, BSAVE, ATTSYNC.
3. **PFGATE** on one plan CBI and one pipe: you want "ready to test".

## 1. PFSELFTEST (every time)

Run it and paste the whole result. Every line is PASS, FAIL (with what it
wanted and what it got) or SKIP (with why).

| Group | What it checks | Was |
|---|---|---|
| 1 Label rows | Per-type prefixes and suffixes, PFELEVPRE, the shared inputs pushed and disagreements reported | B17–B21 |
| 2 Pipe label | Inside the pipe goes back to the centre; outside stays, level, on one leader | F1, F12, F12a |
| 3 PFREFRESH scope | What Line, Selected and Drawing take in | E14–E17 |
| 4 Line tree | Numbering, junction names, crossings left out, headwalls counted | G2 (in part) |
| 5 Grid anchors | The anchor writer and reader, every record, the checks (copy, changed `.pro`, CL typed over), PFREMOVE Anchor and Everything, stubs, a V5 anchor still read | — |
| 6 PFSETUP | Scan (named, `.pro` pair bound, no `.cl` skipped, nothing named twice, grid-name text read); Anchor from a stub and from a blank form; the same line refused; Edit (new name refused, different range refused, a change written in place); a copied anchor named | H1–H3, H7, H10–H13 |
| 7 PFASSIGN | Names by station, a junction on both lines, stations off the `.cl`, face from the through-line, a second run changes nothing, a new structure renumbers the rest, a typed name kept, moved off the line | A2, B15, B16, G5, G7–G10 |
| 8 PFSTRUCT | Four copies (the junction on both grids) at station and rim, the CONST. row, text height, rows at the grid top, PFTOP to the end of row 1, a typed name on its copy, the junction's station rows, a second run places nothing, a copied plan structure warned | A4, A5, B7, G6, C (all) |
| 9 PFREFRESH | 0 updated right after PFSTRUCT; a new rim moves only that copy; a typed row kept; a dragged row and PFDEPTH left alone; PFSTAPRE follows on every copy; a new size follows; moved in plan without PFASSIGN named and not moved, then follows after PFASSIGN; assigned but not placed listed; a copied copy erased; an erased plan structure's copy erased | A6, A8, B1–B6, B8, B10, E1–E6, E11, E12 |
| 10 PFPIPE | The two rows (whole feet, slope to 0.1%), uphill warned, PFLENPRE follows, a stretch updates the length, a new size the diameter; dragged out: arrow on the bottom at the middle, 2.5 long, filled, level landing 1 unit short, left- or right-justified, arrow on the top when above, outside the wall with walls on; 0 updated after; an erased leader redrawn; an erased pipe's leader erased | A7, B11, E7–E9, F2–F10 |
| 11 PFREMOVE | After Remove Anchor, PFREFRESH leaves the released copy alone and PFASSIGN drops the line from the name | H4–H6 |
| 12 Palette | The trees' rows (a gridded line, a line with no grid yet), the panels (datum, stations, `.cl`, a stub's `.pro`, "(not set)"), and a button refusing with the reason. Group 7 also checks Assign for one line | — |

**A FAIL** names what it wanted and what it got: paste it. A whole group
"stopped" is a crash in the suite code; paste that too.

## 2. By hand (what code can't do)

| # | Do this | Expect |
|---|---|---|
| 1 | **PFSETUP Anchor** on a copy of a drawing: pick a stub, fill the dialog, OK, pick lower-left then top-right | The dialog opens with what's known filled in; Browse buttons work; the anchor lands on the corner |
| 2 | **PFSETUP Edit**: click a grid, change the material, tick Re-pick once | "Updated ... in place"; with Re-pick, it asks for the corners |
| 3 | **PFGRIDTEST**: click in a grid, then a few grid lines | Stations and elevations match the grid's own labels |
| 4 | **PFPIPE** by clicking, with S and M | The pipe lands on your clicks; S and M change size and material |
| 5 | **PFREFRESH** Line, clicking a copy, a plan junction, a pipe, its leader and an empty spot in a grid | Each finds its line(s) |
| 6 | **PFREMOVE**: click a grid, Enter (Anchor), Yes; and a copied anchor | The counts it lists look right; the copy is offered on its own |
| 7 | **UNDO once** after PFASSIGN, PFSTRUCT, PFREFRESH, PFPIPE, PFSETUP and PFREMOVE | That whole command goes back |
| 8 | Save, close, reopen, PFREFRESH Drawing | "0 updated" -- nothing changes |
| 9 | Copy a CBI into another drawing, PFSTRUCT then PFREFRESH there | Anything odd? |
| 10 | **PFASSIGN, Yes to TIN rims** | Rims read off the grid's TIN; rims you typed are kept |
| 11 | **PFREFRESH Drawing** and **Line** on the real drawing | Compare the two `Time:` lines |
| 12 | **PFLINETEST** beside V5's labels | Names match. Headwalls show as `(n)  HDWL_.. (not ours)` and take their number. Read "Near a line but NOT on it", "On no line" and "Stacked" -- go and look at each |
| 13 | **Look at** the profile after PFSTRUCT and a dragged pipe label | Rows, text height and the arrowhead look right on paper |

### The palette (2026-11-03)

First, in Studio: the settings in `pf-palette\README.md` ("Studio settings"), then save, then **PFPRELOAD** in AutoCAD.

| # | Do this | Expect |
|---|---|---|
| P1 | **Fresh AutoCAD session**, load, **PFPALETTE**, and make **Scan** the first click | The scan runs and prints, and finishes. (V5's first click of a session died here.) |
| P2 | Click a line on Setup, then on Run | The panels fill; a line with no grid reads "no grid yet" |
| P3 | **Anchor** on a line with no grid yet; **Edit** on one with a grid | The dialog opens; the corner picks work; the palette repaints with the line still picked |
| P4 | **Remove** on a grid, answer No | "Nothing removed." |
| P5 | **Zoom To** on a grid and on a line with no grid | Zooms to the grid / to the line in plan |
| P6 | Run tab: **Assign**, **New Structure**, **Refresh Line** on one line; **Refresh All** | Each says which line it ran on; only that line's structures are named / placed / refreshed |
| P7 | **New Pipe** | PFPIPE's clicks work from the palette |
| P8 | Any button with no line picked | "pick a line in the tree first" |
| P9 | UNDO once after a palette button | That whole run goes back |

## 3. ATTSYNC check (after any block change)

On a **copy** of a drawing:
1. **PFSYNCTEST.** It snapshots every CBI, pipe and anchor and changes nothing.
2. **ATTSYNC** the block(s) you changed.
3. **PFSYNCTEST** again. Every FAIL line names the block and what was lost.
4. **PFREFRESH** Drawing. CBI labels go back against the station line; a dragged pipe label goes back to its spot, level, on its leader.

Paste the result.

## Later, with the pipe work

Invert rows on the CBIs, and which pipe end belongs to which CBI.
