# Diagnostic tools

`pf-load.lsp` loads `Diagnostic_Tools/pf-bench.lsp` last for development checks. Suite modules do not call into it. `PFLOCKATT.lsp` is a separate Block Editor helper and is not loaded automatically.

| Command | Use |
|---|---|
| `PFGATE` | Check a picked structure, pipe, or crossing block against its required tags, properties, and behavior. |
| `PFSELFTEST` | Create temporary test objects, run suite operations and assertions, then clean up. Reports PASS, FAIL, and SKIP. |
| `PFMKATT`, `PFMKPIPEATT`, `PFMKANCATT`, `PFSEL` | Help build and inspect blocks in BEDIT. |
| `PFRECTEST`, `PFSYNCTEST` | Check stored records and ATTSYNC effects. |
| `PFPIPETEST`, `PFGRIDTEST`, `PFLINETEST` | Inspect pipes, grids, and line membership. |

PFSELFTEST defines groups 1–22, 24, and 25. The later groups cover faces (15), invert rows (16), the pipe table (17), plan labels (18), crossings (19), palette reads (20), drawing settings (21), Delete Line (22), design checks (24), and footer behavior (25). Some groups require Carlson and suitable block definitions; SKIP is not a pass.

The test world uses temporary lines and `.cl` files under `%TEMP%\PFSELFTEST`. Dialog clicks, UNDO, save/reopen, ATTSYNC, and live Carlson/OpenDCL behavior need separate interactive checks. The current crossing PFGATE has known ×5/independent-axis and pre-REGEN hatch checks that can falsely fail the accepted ×10 block; see [pf-xing](../pf-xing/README.md).

Load `PFLOCKATT.lsp` separately to lock or unlock selected block attribute definitions in BEDIT.
