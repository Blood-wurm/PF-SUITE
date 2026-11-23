# PFXLABEL: profile crossings

`pf-xing.lsp` loads after pf-invert. **Find Crossings** on the Run tab, or command-line `PFXLABEL`, finds crossings for one selected line. PFREFRESH updates existing marks after pipe changes; it does not find new ones.

## Finding and checking

The tool finds places where another line's `.cl` crosses this line's `.cl`. It skips tie-ins near line ends and junctions near plan structures. The crossing pipe comes from the other line's own `PFSUITE_PIPE` blocks. Without a pipe block there, no crossing mark is drawn.

One `PFSUITE_CROSSING` block is placed at the crossing pipe's inside invert. Clearance is measured **outside to outside** from the pipes' `PFID` and `PFOD` attributes. Below drawing-wide `PFCLRMIN`, the mark is red and reports FAIL. Unknown wall thickness is red and cannot pass. Within `PFCLRWARN` of the minimum, the tool adds a clearance dimension and wall note. The Run list includes crossing rows and status. Rerunning Find Crossings updates matched marks, adds new ones, and removes marks no longer found.

The label names the crossing line and shows the crossing pipe's size and material. It sits to the right by default, scaled by plot text height. Moving `PFLEAD` to the left switches sides; dragging it elsewhere keeps the chosen spot and adds a leader. Hand-edited label text stays.

## Block contract

The canonical file is `blocks/PFSUITE_CROSSING.dwg`. `PFID_X/Y` and `PFOD_X/Y` control the inner and outer ellipse radii. `PFID_INVERT_MOVE` holds the inner invert at the insertion point. `Visibility1` has WALL ON and WALL OFF; WALL OFF is used when OD is unknown. The wall hatch is associative and refills on REGEN. Visible attributes are `PFLABEL` and `PFLABEL2`; hidden values include `PFTYPE`, `PFSIZE`, `PFMAT`, `PFINV`, and `PFCLR`. These block details reflect the last CAD inspection on 2026-11-22; verify any later BEDIT changes in the saved DWG.

Sizing resets the dynamic block, sets the Y radii, measures the result, and adjusts X radii if needed. It reports a size it cannot draw. The current block's four scale actions are uniform, drafted for ×10 vertical exaggeration; other exaggerations are unsupported. The wall state is set after sizing because reset returns it to WALL OFF.

## Remaining limits

- A resized hatch may show its old fill until REGEN. PFXLABEL should run one REGEN after a run that changes crossing sizes.
- PFGATE still checks x5/independent-axis behavior and reads hatch fill before REGEN, so those reports can be false failures for this accepted ×10 block. Its crossing check needs updating.
- The station line (`PFTOP`/`PFBOT`) and `PFSTA1` text are deferred. PFGATE reports them and cannot pass the final crossing gate until they exist.

PFSELFTEST group 19 covers crossing logic. Live Find Crossings and repeated discovery still need a Carlson drawing test; the source and ×10 sizing checks alone do not prove discovery behavior.
