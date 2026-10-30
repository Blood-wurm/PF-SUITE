# pf-record.lsp — the structure record

**Load position:** 5 (after pf-cfg, pf-lib, pf-carlson, pf-files).
**May depend on:** pf-cfg, pf-lib. **pf-cfg must be loaded first**, because this file builds its stored-data key list from pf-cfg's names at load time.
**Depended on by:** pf-index, pf-struct, pf-pipe, pf-bench.

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

## Public API

- **Attributes:** `pfr:attr-ent`, `pfr:get`, `pfr:put`, `pfr:att-style`, `pfr:display-name`, `pfr:tags-ok-p`
- **Stored data:** `pfr:xd-pairs`, `pfr:xd-get`, `pfr:xd-put`, `pfr:ser`, `pfr:deser`, `pfr:memb-get`, `pfr:memb-put`, `pfr:schema-get`, `pfr:schema-put`
- **Tool value vs hand-typed:** `pfr:src-entry`, `pfr:src-get`, `pfr:src-put`, `pfr:refresh`, `pfr:assert`
- **Finding blocks:**
  - `pfr:row-for`: the exact name, or the name plus a number size. Never matched by prefix.
  - `pfr:size-of`, `pfr:ours-p`, `pfr:view`, `pfr:all`, `pfr:read`, `pfr:val`
- **Label positions:** `pfr:att-pt`, `pfr:att-place`, `pfr:moved-p`, `pfr:pos-put`, and `pfr:moved-from-p` (the same "moved by hand?" test for any remembered point, such as the pipe's `PFLEAD` grip)
- **Shared drafter inputs:**
  - `pfr:sync-inputs`: one copy of the logic for the structure's inputs (PFSTAPRE etc.) and the pipe's (PFLENPRE etc.). A new value typed on any block goes to all of them. Two different new values are reported and neither is applied. A value still at the block's own default is not counted as an edit.
  - `pfr:input`: reads one input's value.

## Rules

- **`pfr:refresh` is the rule that makes reruns safe:**
  - a tool value is rewritten on every run;
  - a hand-typed one (ASSERTED) is never touched;
  - a value that no longer matches what the tool last wrote is adopted as hand-typed.
- **Stored data is chunked** under the 255-byte limit. A new key must be added to `*pfr-keys*`.
- **ATTSYNC keeps all of it.** CBI, anchor and pipe were tested with PFSYNCTEST on 2026-10-15.
