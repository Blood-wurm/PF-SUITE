# PFSUITE names and constants

`pf-cfg.lsp` loads first. It defines the block, attribute, dynamic-property, visibility, and stored-data names used by the suite. It also holds label wording, scales, tolerances, block type rules, and drawing-setting defaults.

These names are a drawing contract. Changing a stored name or meaning requires a schema change, not a cosmetic edit. Suite blocks use exact `PFSUITE_<NAME>` names, optionally with a recognized numeric size suffix. `PFSUITE_CROSSING` is the canonical crossing block.

Current drawing settings include plan label height (`PFPLANHT`), minimum vertical crossing clearance (`PFCLRMIN`), warning band (`PFCLRWARN`), minimum pipe slope (`PFSLOPEMIN`), and minimum cover (`PFCOVERMIN`). Pipe sizes and materials come from `pf-cfg/pf-pipes.csv`, read by pf-mats. Unknown wall thickness stays unknown.

Profile text scales from the horizontal plot scale. The plan label height uses its drawing setting. See the corresponding module README before changing a rule here.
