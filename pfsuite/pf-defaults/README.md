# Label defaults and drawing settings

`pf-defaults.lsp` loads after pf-record. It stores preferences in the drawing; the V6.1 palette provides the forms in `pf-palette.lsp`.

## Label defaults

A structure or pipe label input uses the first value found: **line**, then **utility**, then **drawing**, then the block type's built-in default. An explicit saved blank counts as a value. Reset removes the saved value and restores inheritance. A value typed on one block stays on that block.

The Run tab's **Defaults** button opens `pfsDefaults` for the selected gridded line. It lists relevant structure types and pipes, with **Line Default** and **Inherited Default** columns. Save writes changed line defaults in one undo group and refreshes that line; Cancel discards the staged edits. `PFDEFAULTS` offers command-line editing at line, utility, and drawing scopes.

Saved records live in the drawing's `PFSUITE_DEFAULTS` dictionary. `pfv:effective` reads the effective value; `pfv:raw`, `pfv:save`, and `pfv:reset` handle a specific scope. `pfv:inputs` applies values while preserving typed overrides.

## Drawing-wide settings

The Settings tab uses one value per drawing for minimum pipe slope (`PFSLOPEMIN`), minimum cover (`PFCOVERMIN`), vertical crossing clearance (`PFCLRMIN`), crossing warning band (`PFCLRWARN`), and plan label height (`PFPLANHT`). Blank slope or cover disables that check. Cover uses the design TIN; a missing or unreadable surface produces a **cannot check** result.

`pfv:setting-text`/`pfv:setting` read these values and `pfv:settings-save` writes them. The palette validates entries and reports older line/utility settings that V6.1 ignores. The active form is `pfsuite-odcl/pfsuiteV6_1.odcl`; run `PFPRELOAD` after a Studio save.

PFSELFTEST group 13 covers label defaults and typed overrides; group 21 covers drawing settings. The modal Save/Cancel workflow still requires an interactive OpenDCL check.
