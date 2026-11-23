# Line membership and structure names

`pf-index.lsp` loads after pf-anchor. It finds which centerlines a plan structure belongs to, its station on each line, and its built name. Membership (`MEMB`) is stored on the structure, so a junction can belong to more than one line.

The line table uses anchored grids and legacy grid-less stubs. Structures are numbered from the lowest station on each line. A junction name can combine those numbers, such as `BA-5/BC-1`. Only lines of the structure's utility become memberships; another utility meeting it is a crossing.

The `.cl` reader locates points against centerline segments. It checks the file's first point and station range against Carlson; if they disagree or the file contains an unknown row, it walks the line through Carlson instead. This avoids losing structures near a bend. Parsed line geometry is cached for the session by path, timestamp, and size.

## Assignment rules

- A structure within 0.15 ft of a line and within its station range belongs to it. Near misses within 1 ft are reported. Two structures within 0.5 ft are flagged as stacked.
- `pfm:assign` writes the changed structure's type, view, size, line membership, and face. Hand-typed values are preserved by pf-record.
- Each membership records its own face. A CBI with an ambiguous through-line is reported for manual review.
- Legacy `HDWL` blocks still count for numbering through `*pf-count-only*`; current `PFSUITE_HDWL_<size>` blocks are regular suite structures.
- `PFPLABEL` uses the drawing-wide `PFPLANHT` setting and restores a dragged position after ATTSYNC.

`pfm:lines`, `pfm:tree`, `pfm:where`, and `pfm:stale` are the main readers. [PFASSIGN](../pf-assign/README.md) writes the results. The palette assigns the selected line; command-line PFASSIGN can process the drawing.
