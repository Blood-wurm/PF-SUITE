# Shared pipe materials table

`pf-mats.lsp` loads after pf-lib and reads `pf-cfg/pf-pipes.csv`. The Settings tab's **Materials Table** button opens this shared CSV. The suite reads it again when the file changes; it does not write the table. Every drawing using this PFSUITE folder sees the same file.

| CSV column | Meaning |
|---|---|
| `Material` | Pipe label material |
| `Utilities` | Allowed line types, separated by `;`; blank allows all |
| `Default` | `Y` offers the material first for its utilities |
| `n` | Manning's n for export; may be blank |
| `Nominal` | Selected pipe size in inches |
| `ID`, `OD` | Inside and outside diameters in inches; blank ID uses nominal size; blank OD means wall unknown |

Use one row per material and size. The first row for a material supplies its utility, default, and n values. Column order can vary if the header names are correct. Lines beginning with `#` are comments; quoted CSV and UTF-8 BOM are supported. `pft:notes` reports duplicates, invalid diameters, and missing nominal sizes.

The seed table came from Carlson's material and nominal-size data. Most outside diameters were unavailable, so most `OD` cells are blank. The RCP walls seeded from ASTM C76 Wall B still need supplier verification. Unknown wall is never treated as zero or as a passing crossing clearance.

`pft:materials`, `pft:sizes`, and `pft:dims` supply PFPIPE; `pft:n` supplies export. PFSELFTEST group 17 checks parsing and lookups.
