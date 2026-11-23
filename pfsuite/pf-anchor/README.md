# Profile grid reads

`pf-anchor.lsp` loads after pf-defaults. It reads `PFSUITE_ANCHOR` and legacy `PF-ANCHOR`/`PF-GRIDANCHOR` blocks; it never writes them. [pf-grid](../pf-grid/README.md) creates, edits, and removes anchors.

An anchor at the lower-left grid corner supplies the line, station range, datum, plot scales, dimensions, `.cl` path, profile files, TINs, and material. The `.cl` path comes from the `CL` attribute first, then the V6 record, then the V5 ledger. File bindings prefer V6 records and fall back to V5 data.

`pfg:all` finds anchors, `pfg:grid` reads one, and `pfg:anchor-of`/`pfg:anchor-containing` find the grid for a point. `pfg:top-at` finds the highest `PF-GRID-MJR` line above a station; callers handle a missing top.

For many points, build `pfg:index` once and use the `-in` lookup forms. The index is a snapshot: discard it after anchor changes. A copied anchor is detected by a shared creation stamp, not by its handle. PFSELFTEST group 20 compares indexed and direct answers.
