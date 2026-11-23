# Carlson API boundary

`pf-carlson.lsp` loads after pf-mats. It is the only module that calls `cf:road_api` or `cf:dtm_api`; its wrappers return plain data or nil instead of passing API error objects through the suite.

Use `pfc:load` and `pfc:ready-p` before work requiring Carlson. `pfc:metric-p` guards the English-unit workflow. Centerline readers are `pfc:cl-range`, `pfc:cl-locate` (negative offset is left), and `pfc:cl-point`. Surface readers are `pfc:tin-load`, `pfc:tin-z`, and `pfc:tin-unload`.

Carlson can print a failed location request directly to the AutoCAD command line. Callers checking many structures should first narrow candidate points against the `.cl` geometry.
