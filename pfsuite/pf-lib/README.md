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
- **File and grid names (V5's conventions):** `pfl:pro-parts` ("Storm_CA_INV.pro" → ("CA" . "INV")), `pfl:tin-design-p`, `pfl:type-keyword`, `pfl:sheet-type`, `pfl:sheet-name` ("STORM LINE 'DA'" → "DA")
- **Entities:** `pfl:ins`, `pfl:handle`, `pfl:effname` (the real block name, never `*U47`; **every block-name comparison goes through it**), `pfl:bbox`, `pfl:text-len`
- **Dynamic properties (read):** `pfl:dynprops`, `pfl:dynprop`, `pfl:prop-get`, `pfl:dynprop-get`, `pfl:allowed`, `pfl:visprop`
- **Block geometry (read):**
  - `pfl:block-ents`: what is drawn directly in the insert as it shows now, with hidden ones optional
  - `pfl:vlines`
  - `pfl:station-line`: the vertical line at X = 0 first
  - `pfl:geom-pts`, `pfl:geom-ys`, `pfl:geom-bottom`
  - `pfl:end-y`

## Rules

- **Nothing here writes the drawing.**
  - Entities and dynamic properties are written by pf-draw.
  - Attribute values and stored data are written by pf-record.
- **A helper two modules need moves here.** No module keeps a private copy.
- **Hidden entities don't count.** In a dynamic insert's `*U` definition, entities hidden by the current visibility state carry `60 = 1`, and the geometry reads skip them (confirmed by PFGATE's count in CAD, 2026-10-15).
- **Nested blocks and attributes are not the block's own geometry.** A line inside a nested block cannot be stretched.
