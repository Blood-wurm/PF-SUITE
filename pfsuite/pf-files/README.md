# Project file locations

`pf-files.lsp` loads after pf-carlson. It finds the standard folders used by the anchor dialog and remembers the last folder chosen for each file type during the session.

The project root comes from Carlson's `tmpdir$`. Standard subfolders are searched up to three levels above it. A browsed folder is remembered only after the drafter actually selects a file there, so Cancel does not change the next dialog's start location.

Main readers: `pff:root`, `pff:std-dir`, `pff:last-dir`, and `pff:find-in-std`. `pff:browse` prompts for a file and `pff:remember` stores its chosen folder.
