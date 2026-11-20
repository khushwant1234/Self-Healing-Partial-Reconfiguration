# selfheal: notes for Claude

Self-healing DMR FIR accelerator with DFX on PYNQ-Z2 (XC7Z020-1CLG400C),
Vivado 2020.2, hand-written Verilog. Read `docs/STATUS.md` first, then
`docs/BUILD_PLAN.md`. Fault model: `docs/FAULT_MODEL.md`. Registers:
`docs/REGISTER_MAP.md`.

## Two machines
- **Mac** (owner's): RTL, Tcl, Python and docs are written here. No Vivado.
- **Build laptop** (borrowed from a friend, time-boxed, has Vivado 2020.2):
  only runs builds and pushes results back through GitHub.
- The PYNQ-Z2 board is reached by the owner only. Never assume board output;
  ask for it.

## If you are running on the build laptop
- It is someone else's computer. Work only inside this repo. Do not install
  software, change system or global settings, edit PATH/profile files, or set
  `git config --global` without asking first. Use repo-local git config.
- Build only with `scripts/run.sh <target>` (Linux) or `scripts\run.bat <target>`
  (Windows): batch mode only, no GUI. Run it in the background; M0 is about
  15-20 min.
- On Windows the repo must sit at a short path (e.g. `C:\dfx\sh`); the
  preflight refuses long paths.
- After every build, pass or fail: read `reports/<target>/SUMMARY.txt` and
  `vivado.log`, then commit `bitstreams/<target>` and `reports/<target>` and
  push. Never commit `build/`.
- On failure, diagnose from the real log. A fix to Tcl/RTL/XDC may be tried
  on the laptop, but record each attempt (what failed, what changed, result)
  in `docs/STATUS.md` and commit it, so the Mac side sees the history.
- Do not edit `pynq/` from the laptop unless asked; it is tested on the board.

## Status discipline
`docs/STATUS.md` labels: HW-VERIFIED (owner confirmed on board), BUILT,
UNTESTED, BROKEN. Never upgrade a label without evidence.
