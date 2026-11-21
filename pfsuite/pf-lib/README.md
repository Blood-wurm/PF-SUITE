# pf-lib.lsp — the shared engine (READ ONLY)

**Load position:** 2 (after pf-cfg).
**May depend on:** pf-cfg.
**Depended on by:** every other module.

## What it owns

Everything more than one lisp needs, so it is called, never copied (Jake,
2026-10-15). It does the job V5's `pftools-lib` did:
- maths and formatting
- messages
- strings and file reading
- real block names
- reading dynamic properties
- reading a block's own geometry

## Public API

- **Messages:** `pfl:say`. While `*pfl-quiet*` is on, what it's given goes to `*pfl-heard*` (newest first) instead of the command line -- PFSELFTEST reads what a command said that way (2026-10-30)
- **Angles and faces:** `pfl:readable`, `pfl:face-of`, `pfl:face-pair`
- **Profile grid:** `pfl:grid`, `pfl:g`, `pfl:sta->x`, `pfl:elev->y`, `pfl:x->sta`, `pfl:y->elev`
- **Numbers and strings:** `pfl:fix`, `pfl:fmt-sta`, `pfl:parse-sta`, `pfl:number-p`, `pfl:join`, `pfl:join-with`, `pfl:line-parts` ("STORM_AA" → ("STORM" . "AA"), shared by PFSTRUCT and the line tree), `pfl:subst-all`, `pfl:nospace`, `pfl:pad`, `pfl:split`
- **Files:** `pfl:readlines`, `pfl:file-sum` (a text file's checksum)
- **Text:** `pfl:plain-text` strips `%%U` / `%%O` and MTEXT's `\L` `\O` and braces (an underlined grid name, 2026-11-03); `%%D` `%%P` `%%C` are characters and stay
- **File and grid names (V5's conventions):** `pfl:pro-parts` ("Storm_CA_INV.pro" → ("CA" . "INV")), `pfl:tin-design-p`, `pfl:type-keyword`, `pfl:sheet-type`, `pfl:sheet-name` ("STORM LINE 'DA'" → "DA")
- **Entities:** `pfl:ins`, `pfl:handle`, `pfl:effname` (the real block name, never `*U47`; **every block-name comparison goes through it**), `pfl:effname-forget`, `pfl:bbox`, `pfl:text-len`
  - `pfl:effname` is fast (2026-11-20): a name that isn't anonymous is the real name. AutoCAD is asked (`pfl:effname-com`) only for `*` names, and only once per anonymous definition, remembered by its BLOCK record. `pfd:run` forgets the memory at every command start, and the palette at every rebuild. PFSELFTEST group 20 checks every insert against AutoCAD's own answer.
- **Dynamic properties (read):** `pfl:dynprops`, `pfl:dynprop`, `pfl:prop-get`, `pfl:dynprop-get`, `pfl:allowed`, `pfl:visprop`
- **Block geometry (read):**
  - `pfl:block-ents`: what is drawn directly in the insert as it shows now, with hidden ones optional; `pfl:def-ents` the same walk for a block definition by name
  - `pfl:vlines`
  - `pfl:station-line`: the vertical line at X = 0 first
  - `pfl:geom-pts`, `pfl:geom-ys`, `pfl:geom-bottom`; `pfl:sd-pts` (the vertex reader they share)
  - `pfl:nested-bottom`: the lowest point of the plain symbols **nested** in the insert and showing now -- the headwall's profile symbol, which reaches below its flowline (2026-11-17). Read off what shows, so no nested block name is needed outside pf-cfg
  - `pfl:end-y`

## Rules

- **Nothing here writes the drawing.**
  - Entities and dynamic properties are written by pf-draw.
  - Attribute values and stored data are written by pf-record.
- **A helper two modules need moves here.** No module keeps a private copy.
- **Hidden entities don't count.** In a dynamic insert's `*U` definition, entities hidden by the current visibility state carry `60 = 1`, and the geometry reads skip them (confirmed by PFGATE's count in CAD, 2026-10-15).
- **Nested blocks and attributes are not the block's own geometry.** A line inside a nested block cannot be stretched. Only `pfl:nested-bottom` looks inside nested symbols, and only to find how low they reach.

## Added 2026-11-20

- `pfl:csv-split`: one CSV line as Excel writes it (quoted commas, doubled quotes, the UTF-8 marker).
- `pfl:vsegs`, `pfl:walls`: every vertical segment of a block (polyline sides too); the two outer walls and where each stops at the bottom -- how the invert rows read a structure's bottom without nudging PFDEPTH.
- `pfl:leader-path`: the label leader's shape, shared by the pipe label and the crossing label.
