# PFSUITE to Pro-Flow network export — implementation prompt

Use this prompt in the PFSUITE V6 workspace (`E:\Work\Automation\PFSUITE\V6`). Build the PFSUITE side of a versioned JSON exchange for the future Pro-Flow Storm Sewers network. The user chose this exchange as the first integration route. Keep `.stm` support for a later, separate task.

## Goal

Add a command that exports one drawing's storm sewer structures and pipes to a JSON file that Pro-Flow can import without interpreting CAD labels or profile sheet coordinates. Design and document the first exchange version, `pfsuite-proflow-network/1`. This is an interchange file, not a native `.proflow.json` project and not a claim that Pro-Flow's Storm Sewers solver is already built.

Begin with a read-only map of the current source and one representative drawing. Then implement the exporter and a short format specification. Preserve existing PFSUITE commands, V5, and drafter edits. Do not inspect application binaries or decompiled code.

## Existing data authority to verify in source

- A structure's `PLAN` insert (the alpha block) is the authority for its plan XY, attributes, and `MEMB` XDATA. `MEMB` contains `(line station offset)` records; multiple memberships can identify a junction. Profile copies carry `PLAN` and `LINE` links and are not additional structures. Check the actual `PFVIEW` and link handling before selecting entities.
- Structure attributes include `PFNAME`, `PFTYPE`, `PFSIZE`, `PFPOS`, `PFRIM`, `PFSTRUCT`, and `PFINLET`. Use their actual meanings and typed accessors. Do not parse displayed label text as engineering data.
- A `PFSUITE_PIPE` is drawn on a profile grid. `pfp:ends` returns sheet XY; `pfl:x->sta` and `pfl:y->elev` convert through the owning grid to station and invert elevation. The first placed end is treated as upstream and the second as downstream by the current pipe code, but verify endpoint order and report an adverse or ambiguous result rather than silently reversing it. `PFSIZE` is in inches; material text is not a Manning n value.
- The current `pfp:end-at` helper is in an invert-label section marked not yet called. Treat endpoint-to-structure matching as unproven until checked against actual drawings, including multi-line junctions. Resolve through grid/line, station tolerance, and the linked plan structure; never match by name alone.
- The current plan says metric drawings are refused. Respect that guard for v1. Establish what drawing units mean before exporting numbers. Do not infer a coordinate reference system from the filename or coordinates.

## Exchange contract

Write UTF-8 JSON with a top-level `schema` string exactly equal to `pfsuite-proflow-network/1`. Document every field, units, nullability, identifier rule, and validation rule in a nearby markdown spec. Keep the data model independent of AutoCAD handles even while preserving handles as provenance. The file must contain:

1. **Source and units:** PFSUITE version, drawing identity/path, export timestamp, explicit horizontal and vertical units, and CRS status. Use `null` plus an explicit `unspecified` status when CRS or foot definition cannot be established. Store the drawing's unit evidence in provenance.
2. **Structures:** one record per plan structure, with a stable exchange ID, source handle, block/attribute provenance, name/type, plan XY, rim elevation when valid, and all line memberships with stations and offsets. Retain a structure even when a required calculation input is missing; record the missing field.
3. **Pipes:** one record per profile pipe, with a stable exchange ID, source handle, line/grid provenance, end stations, upstream and downstream invert elevations, inside diameter in inches, material text, resolved upstream and downstream structure IDs when unambiguous, and a trustworthy physical/centerline length only if it can be derived from authoritative geometry. A profile label's rounded length and a profile sheet's X distance are not physical plan lengths by themselves. Include the length basis when present.
4. **Unresolved data:** structured `issues` with severity, code, affected entity ID/handle, field, and readable explanation. Represent unknown values as JSON `null`; do not manufacture coordinates, connectivity, length, roughness, catchment inputs, IDF, tailwater, or junction settings. Distinguish a missing source value from a value that exists but fails validation.

Use deterministic output order and numeric values, not formatted station strings. Do not round engineering numbers to the displayed label precision. Avoid storing redundant derived results such as pipe capacity or HGL. If a persistent drawing/entity ID is not available, document the composite identifier and its limits across COPY/INSERT/bind operations; never imply a handle alone is globally stable.

## Behavior and failure policy

- Export is read-only with respect to the DWG. It must not call refresh, rewrite XDATA/attributes, place objects, or change drawing geometry to make an export succeed.
- Save to a user-selected path. Do not overwrite an existing file without an explicit prompt. Validate the completed data before writing; write to a temporary file and replace the destination only after a complete successful serialization.
- Reject a metric or unknown-unit drawing in v1 if values cannot be exported with truthful units. State the reason and leave any existing file intact.
- Emit unresolved links as issues. Do not silently connect a pipe to the nearest structure when more than one match is plausible. Decide and document whether a file with unresolved links is exportable for review, and expose that status in the command's summary.
- Keep PFSUITE-specific metadata under source/provenance fields so Pro-Flow can read the network without needing PFSUITE internals.

## Verification

Use a disposable copy of a representative V6 drawing. Check at least: one pipe between two structures; a structure with two line memberships; no matching endpoint; two plausible endpoint matches; blank or invalid rim; absent diameter; adverse/zero slope; and a metric or unknown-unit drawing. Independently inspect the JSON and compare coordinates, stations, elevations, diameters, material, and link IDs to the drawing. Confirm re-exporting an unchanged drawing produces the same engineering records apart from timestamp/path metadata. Run existing PFSUITE checks relevant to touched modules.

Deliver the command, format spec, one small sanitized example export, and a concise verification report. List each field that Pro-Flow must still supply before Storm Sewers calculations can run, especially Manning n, hydrology/inflow, IDF, tailwater, junction settings, and design criteria. Report any CAD-dependent tests that could not run instead of claiming them passed.
