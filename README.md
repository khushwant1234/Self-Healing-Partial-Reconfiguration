# selfheal: self-healing DMR FIR accelerator with DFX on PYNQ-Z2

Course project: two copies of a FIR filter in two reconfigurable partitions on
an XC7Z020, compared sample by sample. On mismatch, the ARM identifies the
suspect region and repairs it by partial reconfiguration, escalating through
alternate placements, a degraded sequential implementation, and finally
software.

**Current state:** see [docs/STATUS.md](docs/STATUS.md). Nothing has run on
hardware yet.

| Path | Contents |
|---|---|
| `hdl/` | RTL (`hdl/m0/` = toolchain smoke test) |
| `constraints/` | pin and pblock XDC |
| `vivado/` | batch-mode Tcl, one `build_<target>.tcl` per target, plus `common.tcl` |
| `scripts/` | `run.sh` / `run.bat`: one-command unattended build |
| `bitstreams/` | committed outputs: `.bit`, `.hwh`, manifest |
| `reports/` | committed outputs: SUMMARY, step times, utilisation/timing/DRC, Vivado log |
| `pynq/` | on-board Python (`selfheal` package + milestone scripts) |
| `tests/` | off-board Python tests (`make check`) |
| `docs/` | build plan, board setup, fault model, register map, status |

Build on the Vivado machine: `scripts/run.sh m0` (Linux) or `scripts\run.bat m0`
(Windows). See [docs/BUILD_PLAN.md](docs/BUILD_PLAN.md).
