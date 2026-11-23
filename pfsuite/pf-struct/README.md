# PFSTRUCT: profile structures

`pf-struct.lsp` loads after pf-assign. **New Structure** on the Run tab places the selected line's missing profile copies and refreshes that line. Command-line `PFSTRUCT` can work across the drawing. Existing copies are maintained by PFREFRESH.

For each assigned plan structure, PFSTRUCT finds the grid covering its station, inserts one profile copy if absent, fills its saved label defaults, places the label at the grid top, and fits the station line. It reports structures it cannot place. A new copy without a rim uses the grid top and shows a placeholder elevation; without a rim **and** a grid top, placement is skipped.

## Labels and values

The label rows are station(s), construction name, an optional drafter text row, and elevation. The structure type supplies built-in wording such as `CONST. CURB BOX INLET` or `CONST. SANITARY MH`. Saved defaults override those words by line, utility, and drawing. A hand-typed value on one block remains local. A renamed or restationed plan structure reaches its existing copy through PFREFRESH.

Headwalls use their manually entered flowline (`PFRIM`) for the `PFINV1` label and use their sized block name for `PFSIZE`. A sanitary manhole's plan `PFSIZE` selects its cone (`48x24`, `48x30`, or `48x36`); invalid values are reported. Pipe-derived invert rows on other structure types are handled by pf-invert during PFREFRESH.

## Boundaries

- PFSTRUCT places copies; it does not change pipe blocks or plan memberships.
- It keeps hand-moved label rows. It never sets PFDEPTH or the sanitary manhole's floor drop.
- An existing copy whose block type no longer matches its plan source is reported for replacement rather than relabelled as another type.
- `pfs:main-for` handles one line. `pfs:run` returns `(placed already-placed skipped)` for the given plans and grids.

PFSELFTEST groups 8 and 14 cover placement and headwall/sanitary cases. See [pf-invert](../pf-invert/README.md) for pipe-derived elevation rows.
