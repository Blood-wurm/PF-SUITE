# pf-cfg.lsp — constants and names

**Load position:** 1.
**May depend on:** nothing.
**Depended on by:** everything.

## What it owns

Every name typed into the Block Editor, plus the rule tables:
- block names, attribute tags, dynamic parameters and visibility states;
- the stored-data keys;
- the label wording and defaults;
- the scales and tolerances.

## Rules

- **The name contract.** No other file contains these strings as literals.
- **Once a drawing carries a name, changing it is a `*pf-schema*` bump,** not a tidy-up.
- **Every block is `PFSUITE_<NAME>`.** Names are matched exactly, or as the name plus a number size, never by prefix.
- **Text scales with the horizontal plot scale only:** `sf = HPLOT / 20`, text height `1.60 x sf`, and every spacing is a multiple of the text height (as in V5).

## Added 2026-11-20

- Faces: `*pf-face-out*`, `*pf-face-opposite*`. Inverts: `*pf-inv-wall-tol*` `*pf-inv-rim-tol*` `*pf-inv-below-tol*` `*pf-inv-first-shift*` `*pf-smh-barrel-r*`. Plan label: `*pf-tag-plan-label*`. Settings: `*pf-settings*` (PFPLANHT, PFCLRMIN, PFCLRWARN). Pipe: `*pf-pipe-id*` `*pf-pipe-od*`. SECTION 10 the pipe table, SECTION 11 crossings (`PFSUITE_XING` and its names). XDATA `XING`. `*pf-fp-ver*` 6.
- Carlson's pipe library names (`*pf-lib-pipesize*`, `*pf-lib-pipen*`) are gone.
