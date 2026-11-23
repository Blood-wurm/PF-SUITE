# PFASSIGN: plan structures

`pf-assign.lsp` loads after pf-draw. On the V6.1 Setup tab, select a line and choose **Assign Structures** after placing plan blocks. Command-line `PFASSIGN` can assign across the drawing.

Assignment uses [pf-index](../pf-index/README.md) to determine each structure's lines and stations. It writes the built name, membership, type, view, size, face, and optionally rim elevation. The palette reports how many structures were assigned to the selected line. A junction can retain membership on another line while this one is changed or deleted.

## Rules

- Only changed structures are written. Moved structures get new stations; a structure that leaves a line loses that membership. PFREFRESH then removes or updates its profile copy.
- Hand-typed names, faces, and rims stay. A rim is sampled only when requested and a suitable grid TIN can be found; outside that surface, the existing rim remains.
- An ambiguous face is reported for manual entry. Legacy count-only headwalls affect numbering but are not assigned.
- Plan labels receive the structure name at drawing-wide `PFPLANHT` height. A dragged label position survives ATTSYNC.

The palette sequence is **Assign Structures → New Structure**; New Structure refreshes that line after placement. After a plan edit, assign again before Refresh Line. `pfa:line` is the palette entry point; `pfa:run-for` limits writes to one line while preserving drawing-wide numbering. PFSELFTEST group 7 exercises assignment.
