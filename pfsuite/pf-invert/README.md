# Structure invert rows

`pf-invert.lsp` loads after pf-pipe and has no command of its own. PFREFRESH writes `PFINV1` through `PFINV5` on changed profile copies. New Structure on the palette runs that refresh after placement; after command-line PFSTRUCT, run PFREFRESH.

An attached pipe contributes its **end** elevation and nominal size, such as `I.O. 745.10 (15")`. Where a line continues past a structure with no pipe on that side, the structure's bottom supplies an elevation without size. An end above the bottom is a valid drop; an end below it is reported and never moved.

Pipe attachment is measured at the structure wall, within `*pf-inv-wall-tol*` sideways and between bottom and rim. Downstream is left: the left wall is outlet (`I.O.`), the right wall inlet (`I.I.`). Junction rows can include pipes from the other lines' own grids and copies. The tool reads the structure's drawn walls to find its bottom; it does not move PFDEPTH or the sanitary manhole floor drop.

Rows are arranged below the lowest relevant geometry and turned to read upward. Hand-typed rows and dragged positions stay. More than five rows are reported; the extras are not shown. Headwalls keep their own flowline-based `PFINV1` from pf-struct.

These elevations currently live on profile copies, not plan blocks or in PFEXPORT. That transfer needs a separate data and importer decision. PFSELFTEST group 16 covers invert rows.
