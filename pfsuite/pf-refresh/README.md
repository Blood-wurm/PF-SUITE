# PFREFRESH

`pf-refresh.lsp` loads after pf-xing. `PFREFRESH` updates existing profile copies, pipes, crossings, labels, and leaders when their inputs change. It does not place missing structures or discover new crossings; use **New Structure** or **Find Crossings** for those.

## Scope

The command asks for **Selected**, **Line** (default), or **Drawing**. The Run tab's Refresh Line and Refresh All buttons use the corresponding scopes. A line refresh includes crossings on that line and crossings caused by it on another line.

Each tool-created block stores a fingerprint of its inputs. `pfu:copy-due-p`, `pfu:pipe-due-p`, and `pfu:xing-due-p` compare the current inputs with that stamp. The palette uses the same checks for **needs refresh** status. A matching block is left alone; a changed block is redrawn and stamped. The first run on an older drawing may update every block that lacks a stamp.

## Run order

1. Report plan structures moved or added since PFASSIGN. PFREFRESH does not change plan membership or names; run Assign Structures first after plan edits.
2. Remove confirmed orphan and duplicate profile copies. Keep the original copy. Hold and report copies whose plan link is missing or ambiguous.
3. Update changed structure copies, station lines, label rows, and pipe-derived invert rows. Report unplaced structures for New Structure.
4. Update changed pipe geometry, wall, labels, and leaders; erase orphan pipe leaders.
5. Update existing crossing marks and their drawings. Report failed or unknown clearances. Find Crossings is required to discover new marks.

## Preservation rules

Hand-typed label text and dragged labels stay in place. The tool never moves pipe endpoints, changes PFDEPTH, writes plan structure membership, or edits anchors. A dragged pipe label keeps its grip and gets a rebuilt leader; a label inside the pipe returns to its normal position. A released object is excluded from future suite searches.

`pfu:run` returns `(checked updated skipped erased failed)`. Its fingerprint checks and scoped refreshes are exercised by PFSELFTEST groups 3, 9, 11, 19, and 20. CAD behavior still needs an interactive drawing test.
