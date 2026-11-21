# pf-record.lsp — the structure record

**Load position:** 5 (after pf-cfg, pf-lib, pf-carlson, pf-files).
**May depend on:** pf-cfg, pf-lib. **pf-cfg must be loaded first**, because this file builds its stored-data key list from pf-cfg's names at load time.
**Depended on by:** pf-defaults, pf-index, pf-struct, pf-pipe, pf-bench.

## What it owns

**The only file that reads or writes attribute values and stored data
(XDATA).** The record lives on one insert:
- **Attributes:** drafter-visible, editable in Properties, and they come out in data extraction.
- **XDATA (tool only):**
  - `MEMB`: which lines the structure is on, and its station and offset on each
  - `SRC`: what the tool last wrote, per tag, so a hand edit can be told apart
  - `SCHEMA`
  - `PLAN`, `LINE`: a profile copy's link back to its plan structure
  - `POS`: where a label was last put
  - on a grid anchor (2026-10-30): `CL`, `PRO-INV`, `PRO-TOP`, `TIN-EXIST`, `TIN-DESIGN`, `MATERIAL`, `SUMS`, `STAMP`
  - `RELEASED`: left behind by PFREMOVE; every suite search skips it
- **The drawing's own dictionary:** the grid-less line stubs, in V5's format.

## Public API

- **Attributes:** `pfr:attr-ent`, `pfr:get`, `pfr:put`, `pfr:att-style`, `pfr:display-name`, `pfr:tags-ok-p`
- **Stored data:** `pfr:xd-pairs`, `pfr:xd-get`, `pfr:xd-put`, `pfr:ser`, `pfr:deser`, `pfr:val-get`, `pfr:val-put`, `pfr:memb-get`, `pfr:memb-put`, `pfr:schema-get`, `pfr:schema-put`
- **Released (PFREMOVE):** `pfr:released-p`, `pfr:release`. `pfr:all` never returns a released block.
- **`pfr:all` searches our names only** (2026-11-20): `pfr:name-filter` builds the search from `*pf-blocks*`, each root, root + size, and anonymous `*U` (dynamic blocks). `pfr:row-for` still decides what is ours. PFSELFTEST group 20 checks it finds the same blocks as a search of every insert.
- **Line stubs:** `pfr:stub-get`, `pfr:stub-put`, `pfr:stub-del` (key `STUB_<TYPE>_<NAME>`, V5's exact format, read by `pfm:stubs`)
- **Dictionary records:** `pfr:xrec-put d key data` -- create or **replace** an XRECORD, by removing the old one and adding a new one (`entmod` on an existing XRECORD reports success and changes nothing -- PFSELFTEST group 13, 2026-11-17). Used by the line stubs and pf-defaults' saved defaults.
- **Tool value vs hand-typed:** `pfr:src-entry`, `pfr:src-get`, `pfr:src-put`, `pfr:refresh`, `pfr:assert`
- **Finding blocks:**
  - `pfr:row-for`: the exact name, or the name plus a number size -- digits (`PFSUITE_DBI_04`) or a box size, digits `x` digits (`PFSUITE_HDWL_24x36`, any case; `pfr:size-p`). Never matched by prefix.
  - `pfr:size-of`, `pfr:ours-p`, `pfr:view`, `pfr:all`, `pfr:read`, `pfr:val`
- **Label positions:** `pfr:att-pt`, `pfr:att-place`, `pfr:att-move` (the point only -- text, height, rotation and justification untouched), `pfr:moved-p`, `pfr:pos-put`, and `pfr:moved-from-p` (the same "moved by hand?" test for any remembered point, such as the pipe's `PFLEAD` grip)
- **Drafter inputs:**
  - `pfr:sync-inputs`: **diagnostic only since 2026-11-17** -- production inputs come from the saved defaults (pf-defaults) and a typed value stays on its block. PFSELFTEST still uses it to build explicit inputs over its own test blocks: a new value typed on any of them goes to all of them; two different new values are reported and neither is applied.
  - `pfr:input`: reads one input's value.

## Rules

- **`pfr:refresh` is the rule that makes reruns safe:**
  - a tool value is rewritten on every run;
  - a hand-typed one (ASSERTED) is never touched;
  - a value that no longer matches what the tool last wrote is adopted as hand-typed.
- **Stored data is chunked** under the 255-byte limit. A new key must be added to `*pfr-keys*`.
- **ATTSYNC keeps all of it.** CBI, anchor and pipe were tested with PFSYNCTEST on 2026-10-15.
