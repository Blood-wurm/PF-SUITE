# Shared read-only helpers

`pf-lib.lsp` loads after pf-cfg and supplies reusable calculations, readers, formatting, and messages. It does not write drawing entities, dynamic properties, attributes, or records; those writes belong to pf-draw and pf-record.

The main helper groups are:

| Need | Functions |
|---|---|
| Messages and formatting | `pfl:say`, station/number formatters, string and CSV helpers |
| Grid coordinates | `pfl:grid`, `pfl:g`, station/elevation conversions |
| Files and names | `pfl:readlines`, `pfl:file-sum`, line/profile/TIN name helpers |
| Blocks | `pfl:effname`, `pfl:ins`, `pfl:handle`, `pfl:bbox` |
| Dynamic blocks | property readers, allowed values, visibility state |
| Geometry | direct and nested block readers, station line, wall ends, leader path |

`pfl:effname` resolves anonymous dynamic names (`*U...`) to their actual block names and caches the answer for a command or palette read. Geometry readers skip entities hidden by the current visibility state. Nested geometry is read only when needed to find a symbol's lowest point; nested lines cannot be stretched as if they belonged to the outer block.

PFSELFTEST group 20 compares the faster name and anchor reads with AutoCAD's answers. Shared functions belong here when more than one module needs them.
