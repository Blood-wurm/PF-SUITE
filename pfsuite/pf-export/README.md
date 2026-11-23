# PFEXPORT: Pro-Flow exchange

`PFEXPORT` asks for a storm profile anchor. It exports that line and storm lines connected through shared plan-structure membership. Unrelated drawing contents are excluded. The file uses the `pfsuite-network` version 1 contract with `snapshot: "lines"`; each included line is a replacement scope on reimport.

Both pipe invert endpoints must lie in one usable grid. Missing sizes, invalid grids, or no pipes in scope stop the export. Rims are sent as recorded, not calculated. Pipe wall values come from each block's `PFID`/`PFOD`; material options come from the shared pipe table. Profile invert rows are not exported.

The command stages a new UTF-8 file before installing it. Replacing an existing export requires confirmation and keeps a timestamped backup. A live CAD-to-Pro-Flow round trip is still needed before calling this production ready.
