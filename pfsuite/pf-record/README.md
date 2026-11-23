# Attributes and stored records

`pf-record.lsp` loads after pf-files. It is the shared read/write boundary for block attributes, XDATA, and drawing-dictionary records. `pf-cfg.lsp` must load first because record keys are built from its names at load time.

Visible attributes hold values the drafter can edit or extract. XDATA holds membership (`MEMB`), the last tool-written value (`SRC`), schema, profile-to-plan links, label positions, anchor file bindings, and release status. Grid-less line stubs and saved defaults live in drawing dictionaries.

## Rules that protect edits

- `pfr:refresh` updates a value last written by the tool and leaves a hand-typed value alone. If a value no longer matches its `SRC` record, it is adopted as a hand edit.
- `pfr:release` marks an object left in the drawing by Delete Line or PFREMOVE. `pfr:all` skips released objects.
- `pfr:row-for` recognizes exact suite block names and valid numeric size suffixes. It does not match arbitrary prefixes; dynamic `*U` references are resolved to effective names.
- XDATA is chunked to stay under the 255-byte string limit. Add any new stored key to `*pfr-keys*`.

Common entry points are `pfr:get`/`pfr:put` for attributes, `pfr:val-get`/`pfr:val-put` for records, `pfr:all` for active suite inserts, and `pfr:stub-get`/`pfr:stub-put` for line stubs. `pfr:xrec-put` replaces an entire XRECORD; `entmod` is not reliable for updating an existing one.

`pfr:sync-inputs` is diagnostic only. Production labels resolve [saved defaults](../pf-defaults/README.md) per block. PFSYNCTEST checks record survival through ATTSYNC; the recorded CAD result covers CBI, anchor, and pipe blocks.
