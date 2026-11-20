# Project status

Legend: **HW-VERIFIED** = run on the PYNQ-Z2 and output confirmed by Khushwant.
**BUILT** = Vivado produced it, not yet run on the board.
**UNTESTED** = written, never built or run. **BROKEN** = known not to work.

_Last updated: 2026-11-19_

## Environment

| Item | Value | Confirmed |
|---|---|---|
| Vivado | 2020.2, borrowed laptop, batch mode only | yes (version) |
| Laptop OS | ? (Linux or Windows) | **no** |
| Board files tul.com.tw:pynq-z2 | ? (M0 preflight reports it) | **no** |
| PYNQ image version | ? | **no**, outputs not pasted yet |
| Board access / IP | ? | **no** |
| RTL language | hand-written Verilog | yes |

## Milestones

| # | Milestone | State |
|---|---|---|
| M0 | DFX toolchain smoke test (1 RP, inv/buf RMs) | **UNTESTED**: scripts written and dry-run with stubbed Vivado on the Mac; never run in real Vivado or on the board |
| M1 | Static FIR + DMA, bit-exact vs NumPy | not started |
| M2 | DFX with one RP/RM | not started |
| M3 | Two RPs + comparator + interrupt | not started |
| M4 | Full RM library, placement diff evidence | not started |
| M5 | Recovery state machine, latency | not started |
| M6 | Dashboard, Tier-2 injection, write-up | not started |

## What has actually been checked (off-hardware)

- `hdl/m0/*.v`: Verilator lint clean (one intentional PROCASSINIT warning:
  register INIT values are the FPGA power-up state); top elaborates in iverilog
  against a stub of the BD wrapper.
- `vivado/m0/build_m0.tcl` + `vivado/common.tcl`: Tcl dry run with every
  Vivado command stubbed. This proves the step ordering, file plumbing,
  SUMMARY/manifest writing and the Windows long-path guard. It proves
  **nothing** about whether Vivado accepts the commands' options.
- `pynq/selfheal/pl_partial.py`: .bit header parse and .bin word-swap unit
  tests pass on synthetic data (`make check`). Not run against a real bitstream.

## Known risks in M0 (things most likely to fail on first real run)

1. `apply_bd_automation` config keys for PS7/AXI in 2020.2. These are written
   from memory of 2020.x scripts.
2. `write_bitstream -no_partial_bitfile` may be rejected; the script retries
   without it automatically.
3. `pr_verify` report wording is parsed by regex; if unrecognised, SUMMARY says
   UNKNOWN rather than PASS.
4. PYNQ `Bitstream(partial=True)` behaviour on your PYNQ version; `--method
   sysfs` is the fallback path, which bypasses PYNQ entirely.

## Known broken

Nothing yet, because nothing has run yet.
