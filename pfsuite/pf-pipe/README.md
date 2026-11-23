# PFPIPE: profile pipes

`pf-pipe.lsp` loads after pf-struct. **New Pipe** on the Run tab, or command-line `PFPIPE`, asks for the upstream and downstream invert points. Size and material choices come from [pf-pipes.csv](../pf-cfg/pf-pipes.csv), filtered by the grid's utility. The table's default material is offered first.

Each `PFSUITE_PIPE` block stores inside and outside diameters in `PFID` and `PFOD`. The table fills them when the pipe is placed or its size/material changes. A hand-edited value remains local. Blank `PFOD` means the wall is unknown; invert and crossing calculations read the block's values, not a new table lookup.

The two-row label shows construction length and nominal size, then material and slope. Length is rounded to feet and slope to 0.1%. Both rows follow the pipe unless the drafter moves `PFLEAD` outside it; then the tool keeps the chosen spot and draws a leader. A drag inside the pipe returns the label to its normal position. Typed-over text is kept.

The pipe endpoints determine its grid and connections. The tool never moves them during refresh. `pfp:update` redraws the pipe's diameter, wall, label, and leader when needed. A blank or unknown outside diameter never becomes a zero-width wall.

The command uses `pfp:main` for prompts and `pfp:place` for work. `pfp:grid-of-ends-in` and related `-in` readers reuse an anchor index during drawing-wide loops. PFSELFTEST group 10 covers placement and label behavior. The old PFCONVERT source is archived and is not part of the active loader.
