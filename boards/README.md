Optional: put the PYNQ-Z2 board-file folder here (e.g. `boards/pynq-z2/A.0/...`)
and commit it if the Vivado laptop does not have `tul.com.tw:pynq-z2` installed.
The build picks up any sub-folder here via `board.repoPaths`. Without it, the
build still works using a part-only PS7 configuration.
