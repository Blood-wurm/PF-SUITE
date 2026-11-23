# V6.1 OpenDCL palette

`pf-palette.lsp` loads after pf-export. `PFPALETTE` opens or closes `pfsuite-odcl/pfsuiteV6_1.odcl`; `PFPRELOAD` rereads it after a Studio save. The project is `pfsuite` and the palette form is `pfsPalette`.

## Workflow

| Tab | What the drafter does |
|---|---|
| **Setup** | Anchor Grid, place plan structure blocks, select the line in `metaList`, then Assign Structures. Edit Anchor changes grid information or offers Delete Line. The list shows assignment state and points to Run. |
| **Run** | Select a line in `tarLines`. `lvwCommand` lists its structures, pipes, and crossings with stations and status. New Structure, New Pipe, Refresh Line, Find Crossings, Edit Attributes, Defaults, Zoom To, and Refresh All act on the relevant selection. |
| **Settings** | Save one drawing-wide minimum slope, cover, vertical crossing clearance, warning band, and plan label height. Materials Table opens the shared `pf-pipes.csv`. |

The shared footer (`lblStatus`, `txtFeedback`) reports outcomes and errors. Help explains the tabs there. Setup has no Scan, New, Remove, Index, or Zoom To button. Command-line `PFSETUP Scan` and `PFREMOVE` remain available. Delete Line leaves generated objects in place but releases them from future suite refreshes.

The palette caches line and Run-list rows for the active drawing. A drawing change or palette action discards the cache; the next read rebuilds it. Commands always read the drawing directly. File binding checks remain live. Assign Structures reports the count for the selected line from the drawing.

OpenDCL buttons that change the drawing use **Event Invoke = 1** and `pfd:run` for one UNDO group. Selection handlers read only. A control census reports a stale or incomplete form. `PFDEFAULTS` and the Run-tab Defaults button use the `pfsDefaults` modal form; [pf-defaults](../pf-defaults/README.md) stores the values.

PFSELFTEST groups 12, 20, 21, and 25 cover palette reads, cache, settings, and footer logic. Interactive OpenDCL and Carlson checks are tracked in [V6.1 validation](../pfsuite-md/V6.1-VALIDATION.md).
