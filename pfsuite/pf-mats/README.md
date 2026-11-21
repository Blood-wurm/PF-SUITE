# pf-mats.lsp — the pipe table

**Load position:** 3 (after pf-lib).
**May depend on:** pf-cfg, pf-lib.
**Depended on by:** pf-index (settings), pf-pipe, pf-invert, pf-xing, pf-export, pf-bench.

## What it owns

**One table of pipe materials and sizes, kept with the lisp** (Jake, 2026-11-20):
`pf-cfg\pf-pipes.csv`. Every drafter reads the same file — the problem with
Carlson's per-user `pipesize.dta` / `pipen.dta`, which are no longer read.

Edit it in Excel or Notepad. One row per material and size:

| Column | Meaning |
|---|---|
| Material | Exactly what prints on row 2 of the pipe label (`PFMAT`) |
| Utilities | Which line types PFPIPE offers it for, `;` between them (`STORM;SANITARY`). Blank = every type |
| Default | `Y` = PFPIPE's first choice for those utilities. One per utility |
| n | Manning's n, for exports. May be blank |
| Nominal | The size picked and printed, inches |
| ID / OD | Inside / outside diameter, inches. Blank ID = the nominal. **Blank OD = wall unknown** |

- A material's Utilities, Default and n are read from its **first** row.
- Lines starting with `#` are notes.
- Columns may be in any order; the header names them.
- Excel's quotes and its UTF-8 marker are handled (`pfl:csv-split`).
- Read again whenever the file changes — no reload needed.
- Problems (a size twice, an OD not bigger than the ID, no Nominal) are listed by `pft:notes`, printed by PFPIPE and PFGATE.

**Seeded 2026-11-20** from Carlson's files: their 10 materials (with n) × 21
round sizes. Carlson had no walls, so OD is blank — except RCP III / IV / V,
seeded from ASTM C76 Wall B (wall = size/12 + 1"). **Check those against your
supplier and fill in the rest.**

## Public API

`pft:path`, `pft:table`, `pft:parse` (pure — PFSELFTEST hands it lines),
`pft:notes`, `pft:default-notes`, `pft:mats-all`, `pft:mat`, `pft:materials`,
`pft:default`, `pft:sizes`, `pft:dims`, `pft:wall`, `pft:n`, `pft:num`

## Rules

- **Read only.** The tool never writes the table.
- **A wall not on record is unknown, never zero.** A crossing on it is UNKNOWN, never a pass.
- **The pipe block keeps its own numbers** (`PFID` / `PFOD`, pf-pipe). The table only fills them in.

PFSELFTEST group 17.
