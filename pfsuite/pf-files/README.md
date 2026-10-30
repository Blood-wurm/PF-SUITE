# pf-files.lsp — where the file dialogs open

**Load position:** 4 (after pf-carlson).
**May depend on:** pf-cfg.
**Depended on by:** pf-anchor, pf-assign, pf-bench.

## What it owns

Project folders, ported from V5's `pfsettings`:
- the project root is Carlson's `tmpdir$`;
- each file type has the firm's standard subfolder, searched up to 3 levels above the root;
- the folder last browsed to is remembered for the session.

## Public API

`pff:root`, `pff:root-set`, `pff:std-dir`, `pff:last-dir`, `pff:dir`,
`pff:remember`, `pff:browse`, `pff:find-in-std`

## Rules

- **The remembered folder is written only with the folder actually chosen.** That fixes V5's LOW-3.
