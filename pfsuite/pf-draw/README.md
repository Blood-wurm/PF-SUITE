# pf-draw.lsp — the drawing boundary (NO COMMANDS)

**Load position:** 8 (after pf-lib, pf-record, pf-anchor, pf-index).
**May depend on:** pf-cfg, pf-lib.
**Depended on by:** pf-assign, pf-struct, pf-pipe, pf-bench.

## What it owns

**The only file that creates, moves or erases entities, or sets a dynamic
property.** It does the job of V5's `pfdraw`, plus V5's `pf:run-command`: the
one wrapper every command runs inside.

## Public API

- **The command wrapper**
  - `pfd:run name fn`: one UNDO group around the whole command. An error or Esc still closes it, and an error names the stage it was in.
  - `*pfd-stage*`: what the command is doing now. Each step sets it as it starts.
  - `pfd:try label fn args`: one structure or pipe that fails is reported and skipped, and the run goes on.
- **Dynamic properties (write):** `pfd:prop-put`, `pfd:dynprop-put`, `pfd:set-state`
- **Entities:** `pfd:insert`, `pfd:move`, `pfd:erase`
- **Station line:**
  - `pfd:fit-end`: fits the station line's top with PFTOP. It measures, sets, measures again, and self-corrects the direction.
  - `pfd:depth-probe`: PFGATE's check that the PFDEPTH grip moves the barrel. It nudges the value and puts it back.

## Rules

- **No commands here.** Commands live in their own modules and call down.
- **Every command body runs inside `pfd:run`.**
- **The tool never sets PFDEPTH.** The barrel depth is the drafter's, set with the grip (Jake, 2026-10-15).
- **Reading dynamic properties is pf-lib's,** not this file's.
