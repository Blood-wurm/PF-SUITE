# Grid setup and removal

`pf-grid.lsp` owns grid anchors and the `pf-grid.dcl` record dialog. It loads after pf-refresh. Anchor reads live in [pf-anchor](../pf-anchor/README.md).

## Setup workflow

On the V6.1 palette, **Anchor Grid** opens a blank record dialog, then asks for the grid's lower-left and upper-right corners. The drafter places structure blocks in plan, selects the line, and chooses **Assign Structures**. **Edit Anchor** changes the selected grid's record or offers **Delete Line**.

The command-line `PFSETUP` still offers `Scan`, `Anchor`, and `Edit`. Scan reads `PF-NAME` text, finds the matching `.cl` and `_INV`/`_TOP` `.pro` files, and creates grid-less line stubs. It is a legacy command option, not a palette step. Anchor can use a stub or a blank form. Edit updates an existing anchor.

An anchor is `PFSUITE_ANCHOR` at the lower-left grid corner. Its attributes hold line, utility, station origin, datum, plot scales, dimensions, and the `.cl` path. Its records hold profile and TIN paths, material, file checksums, creation stamp, and schema. The block definition must have all required tags before placement. `PFMKANCATT` adds missing tags in BEDIT.

## Removal

**Delete Line** previews the full line footprint and asks for confirmation. It erases that line's anchors and stub, removes its plan-structure memberships, and releases generated drawing objects in place. Junctions keep their associations with other lines. Future refreshes skip released objects. One UNDO restores the line.

`PFREMOVE` is a separate command-line tool. Its **Anchor** mode erases one anchor and releases the objects on that grid; **Everything** erases those objects too. A copied anchor can be removed alone. Deleting a line and removing one grid have different scopes.

## Checks and limits

- A line's name and utility identify it. Edit rejects changes to either and rejects a `.cl` with a different station range.
- Profile files and TINs bind in pairs. Scan reports missing or ambiguous `.cl` files instead of guessing.
- Anchor checks flag copied anchors, unreadable values, missing or changed source files, a mismatched `CL` attribute, and a moved or stretched grid.
- Existing V5 anchors remain readable and receive V6 records when edited.

The main work functions are `pfn:place-rec`, `pfn:edit-check`, `pfn:edit-write`, `pfn:delete-line`, and `pfn:remove`. PFSELFTEST groups 5, 6, 11, and 22 cover placement, legacy Scan, removal, and Delete Line.
