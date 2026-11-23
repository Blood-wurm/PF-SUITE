# Drawing writes and command wrapper

`pf-draw.lsp` loads after pf-index. It owns drawing entity changes and dynamic-property writes. Read-only geometry and property helpers live in pf-lib; attribute and XDATA writes live in pf-record.

`pfd:run` wraps command work in one UNDO group and closes it after an error or Esc. `*pfd-stage*` names the current step in an error report. `pfd:try` reports a failed individual item and lets the rest of a run continue.

The module inserts, moves, scales, and erases blocks; writes lines, polylines, text, and crossing dimensions; changes dynamic states; and creates needed layers. `pfd:layer` does not overwrite an existing layer's color or plot setting. `pfd:fit-end` measures and adjusts a station line's `PFTOP` end. `pfd:depth-probe` is a diagnostic check that restores its temporary change.

This file has no user command. It never sets PFDEPTH during normal work; that grip belongs to the drafter.
