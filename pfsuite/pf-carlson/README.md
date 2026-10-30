# pf-carlson.lsp — every Carlson API call

**Load position:** 3 (after pf-lib).
**May depend on:** pf-cfg.
**Depended on by:** pf-index, pf-assign, pf-struct.

## What it owns

**The only file that names `cf:road_api` or `cf:dtm_api`.** Every wrapper
returns plain data or nil, never an error object.

## Public API

- **Setup:** `pfc:load`, `pfc:ready-p`, `pfc:metric-p`
- **Centerlines:** `pfc:cl-range`, `pfc:cl-locate` (signed offset: left is negative), `pfc:cl-point`
- **Surfaces:** `pfc:tin-load`, `pfc:tin-unload`, `pfc:tin-z`

## Rules

- **A failed location request makes Carlson print to the command line,** below LISP, where it can't be stopped. Callers asking about many structures need a pre-filter first. V5 used a corridor around the `.cl` shape.
