# pf-xing.lsp — PFXLABEL: crossings, clearance checked

**Load position:** after pf-invert, before pf-refresh.
**May depend on:** everything up to pf-invert.
**Depended on by:** pf-refresh, pf-palette, pf-bench.

## What it owns

**PFXLABEL** (Jake, 2026-11-20) on **one line** — the one picked in the
palette (Crossings button), or clicked at the command line. Drawing-wide may
come later.

1. **Finding them** (V5's discovery): every place another line's `.cl` crosses this one's. Not within 2 ft of either line's end (a tie-in), not within 5 ft of a plan structure (a junction) — each skip is said.
2. **The crossing pipe** comes from **that line's own `PFSUITE_PIPE` blocks**, on its own grid. **No pipe block there, nothing is drawn.**
3. **This line's pipe** at the crossing, from its pipe blocks.
4. **One `PFSUITE_XING` block** per crossing, inserted at the crossing pipe's **invert**.
5. **The clearance, outside to outside**, from both pipe blocks' `PFID` / `PFOD`:

| Result | What shows |
|---|---|
| Short of `PFCLRMIN` | Block and drawings **red**; `FAIL  15.6"` in the palette and the run |
| A wall not known (`PFOD` blank) | **Red**; `FAIL  wall unknown` — never a pass |
| Otherwise | `PASS  22.4"` |
| Within `PFCLRWARN` of the minimum, or short | A **dimension** from the outside of this line's pipe wall, `PFCLRMIN` long, toward the crossing pipe, reading `18" MIN.`; ticks at that wall's inside and outside, and the note `2.5" WT. (18" RCP)` |
| No pipe on this line there | Drawn, clearance not checked, said |

`PFCLRMIN` (18) and `PFCLRWARN` (6) are settings — the Defaults dialog, by line, utility or drawing.

**Run again:** the same crossings are updated (matched by crossing line and
station), new ones placed, ones no longer there (or with no pipe block now)
erased. **PFREFRESH keeps every crossing block up to date** when a pipe at it
changes — on a Line refresh of either line. Only PFXLABEL finds new crossings.

## The label

- **Rows:** V5's wording by the crossing line's utility — `PROP. WATER MAIN 'A'` — then the crossing pipe block's size and material, `16" C900 DR 14 PVC` (the block is the source).
- **Station text:** V5's vertical `4+50.00 PROP. WATER CROSSING` at the bottom of the station line, which runs from below the grid up to the grid top.
- **Placement:** left of the ellipse by default; the flip grip puts it right. Dragged anywhere else, it stays there on a **leader** the tool draws — its arrow 1 unit (at 1"=20') off the ellipse, half way up.
- Text typed over is kept.

## The block (Jake draws it)

`PFSUITE_XING`, insertion point at the pipe's **invert**. Everything on layer 0, colour **ByBlock**.

| Name | Type | Action | Notes |
|---|---|---|---|
| `PFDIA` | Linear | **Scale** on the ellipse, base **Independent** at the insertion point | Ellipse drawn 1 ft wide x 10 tall, bottom on the insertion point. Value = inside diameter, ft |
| `PFODTOP` | Linear, vertical, up from the insertion point | **Move** on the top tick | Value = (ID + wall) x 10. Tool-set |
| `PFODBOT` | Linear, vertical, down from the insertion point | **Move** on the bottom tick | Value = wall x 10. Tool-set |
| `PFTOP` | Linear, vertical | **Stretch** the station line's top | To the grid top |
| `PFBOT` | Linear, vertical | **Stretch** the station line's bottom, **Move** `PFSTA1` | Below the grid |
| `PFLEAD` | Point | **Move** on `PFLABEL`, `PFLABEL2` | The label grip |
| `PFFLIP` | Flip, line vertical through the insertion point | **Flip** on both label rows and `PFLEAD` | Left / right |

Attributes: `PFLABEL`, `PFLABEL2`, `PFSTA1` (visible); `PFTYPE`, `PFSIZE`,
`PFMAT`, `PFINV`, `PFCLR` (hidden). Ticks: short level lines, fixed length.

**PFGATE** checks it: every tag and parameter, PFDIA growing the ellipse up,
PFTOP / PFBOT moving the station line.

## Public API

`pfk:run` (the work, no questions — the palette and PFSELFTEST), `pfk:main`,
`pfk:all`, `pfk:on-line`, `pfk:rec`, `pfk:extras`, `pfk:extras-of`,
`pfk:data`, `pfk:fp`, `pfk:update`, `pfk:stamp`, `pfk:status`, `pfk:clear`,
`pfk:hits`, `pfk:find`, `pfk:pipe-at`, `pfk:words`, `pfk:setting`

## Rules

- **Pipe blocks only.** No pipe block, no crossing.
- **Everything the tool draws carries the block's handle** (XDATA `XING`): redrawn with its block, erased when the block is gone.
- **The ellipse assumes x10.** A grid with another exaggeration is said.

PFSELFTEST group 19.
