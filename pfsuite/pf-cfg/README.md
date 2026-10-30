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
