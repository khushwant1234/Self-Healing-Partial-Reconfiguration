# Build plan and laptop workflow

## The laptop session, every time

```
git pull
scripts/run.sh <target>          # Linux
scripts\run.bat <target>         # Windows
git add bitstreams/<target> reports/<target>
git commit -m "<target> build results"
git push
```

`run` is unattended: it sources Vivado if needed, runs the batch Tcl, copies
the Vivado log into `reports/<target>/vivado.log`, and prints `SUMMARY.txt`.
It writes a SUMMARY on failure too, so **always push, even after a failure**.
That log is what I need to diagnose it.

Nothing in any target uses the GUI or the DFX wizard. If a future step cannot
be scripted, it will be flagged in this file and in the milestone instructions
**before** your session.

### Windows only

* Clone to a short root: `git clone <url> C:\dfx\sh`. Generated IP paths add
  ~170 characters under `build\`, and the 260-character limit fails as an
  unrelated-looking synthesis error. The preflight step refuses to start if
  the build path is longer than 60 characters on Windows.
* If the clone must live somewhere long, set `SELFHEAL_BUILD_ROOT=C:\b`
  before running; only the gitignored build tree moves.
* `.gitattributes` forces CRLF on `.bat` files. If `run.bat` prints garbage,
  run `git config core.autocrlf true` then re-clone.

### Board files

The preflight step looks for `tul.com.tw:pynq-z2`. If it is missing, the build
**continues** with a part-only PS7 configuration (GP0 master and FCLK0 =
100 MHz set explicitly). That is enough for PYNQ, because the board's Linux
has already configured DDR and MIO; a PL bitstream does not touch them. To use
the real board preset without installing anything on the laptop, put the
board-file folder under `boards/` in this repo and commit it.

## DFX configuration plan (full project, M4 onward)

Partial bitstreams are not relocatable on 7-series, so every RM is implemented
separately in RP_A and in RP_B. One configuration places one RM in each RP,
so the number of configurations is the number of RMs per RP, **not** RMs x RPs.

RM library per RP (pending the decision in `FAULT_MODEL.md`):
`golden_pA, golden_pB, faulty_pA, faulty_pB, sequential, blank` = 6 RMs.

| Config | RP_A | RP_B | Kind |
|---|---|---|---|
| P  | golden_pA  | golden_pA  | **parent**: full place & route, static locked afterwards |
| C1 | golden_pB  | golden_pB  | child |
| C2 | faulty_pA  | faulty_pA  | child |
| C3 | faulty_pB  | faulty_pB  | child |
| C4 | sequential | sequential | child |
| C5 | blank      | blank      | child |

That is 1 parent + 5 children. The pairing inside a row does not matter at run
time: each RP's partial is loaded independently, so any combination works.
Outputs: 1 full bitstream + 12 partials. The parent holds the largest RM
(parallel golden) so the static routing is decided around the worst case.

The RP_A and RP_B modules get distinct names (`rp_a`, `rp_b`, thin wrappers
around one shared core). Two black-box instances of the same module in two RPs
is a configuration I do not want to discover Vivado's opinion of mid-session,
so each RM is synthesised out-of-context twice. That is cheap.

### Time estimates (to be replaced by measured numbers)

These are estimates for a mid-range 4-core laptop with 16 GB RAM. M0 records
real per-step times in `reports/m0/step_times.txt`. After the first run I will
rescale this table from those numbers.

| Step | Count | Each | Total |
|---|---|---|---|
| Static synth (PS7, DMA, interconnect, regs, comparator) | 1 | 6-10 min | 6-10 min |
| RM out-of-context synth | 12 | ~1 min | ~12 min |
| Parent implementation | 1 | 8-12 min | 8-12 min |
| Child implementation | 5 | 4-7 min | 20-35 min |
| Bitstreams (1 full + 12 partial) | 6 configs | ~1 min | ~6 min |
| pr_verify | 1 | 1-2 min | ~2 min |
| **Full rebuild** | | | **~55-80 min** |
| One RM changed, static untouched | | | **~8-10 min** (2 synths + 1 child + bitstreams) |

**Rule:** any static change invalidates every partial. The manifest records
the build and git revision; never mix partials from different builds. From M2
onward a `BUILD_ID` register lets Python refuse a mismatched set.

## M0 smoke test (first laptop session)

`scripts/run.sh m0` / `scripts\run.bat m0`, about 15-20 minutes estimated:
static synth ~5 min, 2 RM synths ~1 min each, parent impl ~4 min, child impl
~3 min, bitstreams ~2 min, pr_verify ~1 min.

It proves in one run that:

* Vivado 2020.2 runs the non-project DFX flow in batch on this install;
* the Zynq part is installed, and whether the board files are (preflight line);
* bitstream generation needs no extra licence (DFX has been free in all
  editions since 2019.1; a licence failure would stop at `write_bitstream`);
* path handling works on this OS.

The board half of the test then shows PYNQ loading those partials.
