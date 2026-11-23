# PFSUITE block library

Each block now has its own authoring drawing in `blocks/`, named after its
definition. Add future blocks as separate drawings there. The combined
`blocks/PFSUITE_BLOCKS.dwg` is retained as the pre-split source/reference; do
not use it for new block edits. Use disposable test drawings for validation.

## Current inventory (2026-11-22)

AutoCAD read the following named definitions from the combined library and
split each into a separate DWG:

| Family | Definitions |
|---|---|
| Existing baseline | `PFSUITE_CBI`, `PFSUITE_PIPE`, `PFSUITE_ANCHOR` |
| Headwalls | `PFSUITE_HDWL_12`, `_15`, `_18`, `_24`, `_30`, `_36` |
| Sanitary | `PFSUITE_SMH` |
| Crossing | `PFSUITE_CROSSING` (created separately on 2026-11-22) |

Each matching `blocks/PFSUITE_<name>.dwg` contains its named
`PFSUITE_*` definition and a model-space sample. The ten drawings split from
the combined library were saved on 2026-11-21. A read-only AutoCAD comparison
against that library passed 10/10: definition and sample counts, attribute tags, dynamic
property names, entity types, and hatch associativity matched. The two pipe
wall hatches remained associative. The split used copies of the saved library
with the other samples and block definitions purged, because a direct WBLOCK
of the CBI was rejected by a proxy object. Dynamic grip movement and the full
placement/refresh workflow still need their existing functional checks.

The headwall family is complete for the current scope. No additional headwall
sizes are on the remaining-block list.

The draft headwall and sanitary libraries had no additional named `PFSUITE_*`
definitions. Their corresponding definitions had matching counts and normalized
entity data in AutoCAD. This comparison did not inspect every dynamic block
action or extension dictionary, so `PFGATE` and a real workflow check remain
required before production use.

The two draft libraries, their backups, the damaged recovery drawing, and the
two small review drawings and backups were removed from this folder after being
archived at `E:\Work\Automation\PFSUITE\Archive\redundant-block-drawings-2026-11-21.zip`.
The archive's source hashes are in the adjacent `.sha256.txt` file. The large
`PFSUITE_SANITARY_REVIEW.dwg` was left alone because its contents have not been
classified as a disposable block sample. `V6_Test.dwg` and the open disposable
review copy were also left alone.

## Remaining definitions and checks

The code also declares `PFSUITE_CBI_BOX`, `PFSUITE_DBI`, `PFSUITE_DMH`, and
`PFSUITE_MH`. They are not in the current library. Confirm which of these
candidate definitions the drafting workflow actually needs before drawing them.

`PFSUITE_CROSSING` is authored in `blocks/PFSUITE_CROSSING.dwg`, outside the
older combined library. Its ellipse, wall, and label contract is documented in
`pfsuite/pf-xing/README.md`; the station line remains deferred.

For each definition: agree on source geometry and dimensions, build it in
its own `blocks/PFSUITE_<name>.dwg`, check tags and dynamic properties with `PFGATE`, run
`PFSYNCTEST` around `ATTSYNC`, then exercise its plan/profile placement and
`PFREFRESH` in a disposable test drawing. Run the Carlson-dependent part of
`PFSELFTEST` in the target host before calling the family ready.
