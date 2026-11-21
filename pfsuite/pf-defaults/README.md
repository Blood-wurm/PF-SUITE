# pf-defaults.lsp — saved label defaults

**Load position:** 6 (after pf-record).
**Prefix:** `pfv:`.
**May depend on:** pf-cfg, pf-lib, pf-record.
**Depended on by:** pf-struct, pf-pipe (`pfv:inputs`, `pfv:fp-inputs`), pf-palette (the Defaults dialog and `PFDEFAULTS`), pf-bench (PFSELFTEST group 13).

## What it owns

The drafter inputs on a profile copy or pipe (Station Prefix, Construction Suffix, Length Prefix and the rest) take their value from the first one found:

1. the **line's** saved default,
2. the **utility's** (STORM, SANITARY …),
3. the **drawing's**,
4. the block type's **built-in** default (`*pf-type-fmt*` over `*pf-fmt-defaults*`, `*pf-pipe-fmt-defaults*` in pf-cfg).

A value typed on one block stays on that block (Jake, 2026-11-17). This replaces the 2026-10-27 rule that pushed a typed value to every block of the same type.

Saved defaults live in the drawing, in the `PFSUITE_DEFAULTS` dictionary, one record per utility / line / kind / block type / tag. A saved blank is a real default. Reset removes the record.

This file only stores and looks up. The **Defaults** dialog and the `PFDEFAULTS` command are in pf-palette, because they read structures, grids and pipes and run PFREFRESH (2026-11-17, so the load order holds).

## API

| Function | Does |
|---|---|
| `pfv:effective line kind ty tag fallback` | the value that applies on that line |
| `pfv:effective-for util line kind ty tag fallback` | the same from a given utility and line; `""` skips a level (the dialog's Inherited Default) |
| `pfv:raw util line kind ty tag` | what is saved at exactly that level, or nil |
| `pfv:save` / `pfv:reset` | write (create or replace, via `pfr:xrec-put`) / remove one record |
| `pfv:inputs e line kind ty tags base` | fills a block's inputs from the defaults, keeping typed values; an old value typed before provenance existed is adopted as typed |
| `pfv:fp-inputs …` | the same, read only, for the fingerprint |
| `pfv:utility line` | `STORM` from `STORM_BA` |

## The Defaults dialog

Select a gridded line on the palette's Run tab and click **Defaults**. The modal `pfsDefaults` form lists only structure types whose plan blocks are assigned to that line, plus the pipe fields if a pipe has both endpoints on one usable grid of that line. Rims are user driven and are not included.

The form is populated when it opens. Editing the Grid changes only the form. **Save** reads the editable Line Default cells, closes the form, and writes changed line defaults to this DWG in one undo group. It then refreshes that line if every save succeeded. **Cancel**, Escape, or closing the window discards the staged changes. Existing hand-edited block attributes stay local.

The visible Grid columns are **Block type**, **Setting**, **Line Default (edit)**, and **Inherited Default**. For headwalls, the elevation prefix and suffix appear as **Invert Prefix** and **Invert Suffix**; they control the profile invert label (`PFINV1`). A heading separates each structure type and pipes. Saved keys remain the attribute tags.

**Use inherited default** in **Line Default (edit)** means no line value is stored. Replace it with a value to override; an empty cell stores an explicit blank. Type `Use inherited default` again (or `<inherit>`) to reset.

`PFDEFAULTS` is the command-line fallback; it can also edit drawing and utility scopes.

## OpenDCL Studio wiring still needed

The binary `pfsuite-odcl/pfsuite.odcl` needs two controls added in Studio. The LISP cannot create OpenDCL controls at runtime.

1. On the `pfsPalette` Run tab add a button named exactly `btnDefaults`, caption **Defaults**, with Clicked ticked and **Event Invoke = 1**.
2. Add a **Modal Dialog** form named exactly `pfsDefaults`, titled **PFSUITE Defaults**. Add a Grid named `grdDefaults` with seven columns in this order: `Scope`, `Utility`, `Line`, `Block`, `Tag`, `Saved`, `Effective`. Column Header on, Row Header off, Sorting off, Text style for Saved. The LISP sets captions and widths at runtime.
3. Add buttons named exactly `btnSave` and `btnCancel`, captions **Save** and **Cancel**. Tick Clicked on both. Tick Initialize on the form. The handlers are in `pf-palette.lsp`; do not generate replacements.
4. Save the project, load `pf-load.lsp`, run `PFPRELOAD`, and reopen `PFPALETTE`.

## Tests

PFSELFTEST group 13: the look-up order on a made-up type and utility (nothing real read or written), saved blanks, reset, the dialog's Inherited Default, and on two test CBIs a typed value kept against an old tool value replaced. Left by hand: the dialog itself (Save while a cell is being edited, Cancel, the final refresh).

## Existing drawings

Under the old push (`pfr:sync-inputs`), a value typed on one block was copied onto every block of its type **and recorded as tool-written on all of them, the typed one included**. So on a drawing refreshed before 2026-11-17, the next PFREFRESH sets every one of them back to the saved or built-in default. **To keep such wording, save it in Defaults (drawing or utility scope) before refreshing.**
