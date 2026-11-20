# Fault model

**What this project demonstrates:** the detection, arbitration and repair
*mechanism*, and its measured latency. **What it does not demonstrate:**
recovery from a real silicon defect. Every fault is injected or emulated, and
this is stated in the write-up.

## Why the ladder needs an explicit fault model

A configuration-memory upset (Tier 2) is cleared by reloading *any* bitstream
into the region, including the identical one. Under that fault alone, ladder
step 2 always succeeds and steps 3-5 are unreachable. A real defect persists
across reloads. So each ladder step needs an injected fault that it is the
first step able to repair.

## Proposed table (draft, decisions marked OPEN)

| # | Injected fault | Mechanism | Expected ladder depth | Demonstrates |
|---|---|---|---|---|
| 1 | Transient upset in RP_A | Tier 2 bit-flip (M6). **Until then:** static-side `INJECT.transient_A` XORs RP_A's output until the next recouple of RP_A, so any reload clears it | Step 2: reload same RM | Transient / SEU recovery |
| 2 | "Defect" at placement pA in RP_A | Defect map {A:pA}: loading golden_pA into RP_A loads faulty_pA, which has golden_pA's placement and corrupts its output while `INJECT.arm_A` is set | Step 3: load golden_pB | Placement relocation |
| 3 | Defects at pA and pB in RP_A | Defect map {A:pA, A:pB} | Step 4: fir_sequential | Graceful degradation |
| 4 | Whole region RP_A dead | Defect map {A:pA, A:pB, A:seq}; see OPEN-2 | Step 5: blank RP_A, simplex on RP_B (or PS software FIR if both regions are dead) | Survivability |

### How the defect map works

`faultinject.py` holds a per-region set of "defective placements". The
recovery state machine asks for a logical RM ("golden_pB into RP_A").
`reconfig.py` resolves it, and if that (region, placement) is in the defect
map, it loads the faulty twin instead and **logs the substitution**. The
ladder's decisions stay real: it only sees mismatches and the software
reference. The defect is emulated, and the logs and the write-up say so.

### OPEN decisions (need your call before M4)

* **OPEN-1, reading of your row 3.** I read "faulty variants in both RPs" as
  "both placements in the *same* RP are defective" (row 3 above). If faulty
  RMs were really loaded into RP_A *and* RP_B with identical corruption, the
  DMR comparator would see agreement and detect nothing. Confirm the
  same-RP reading.
* **OPEN-2, reaching step 5 naturally.** For the ladder to reach step 5
  without a "force" flag, fir_sequential also needs a defective twin
  (`faulty_seq`), which makes 7 RMs and one more child config (about 5 min).
  The alternative is a `force_dead` command that skips straight to step 5.
  Recommendation: `faulty_seq`, because it keeps the whole ladder
  data-driven.

## Suspect arbitration (agreed approach)

On a mismatch, the PS runs the NumPy reference on the input window around
`MISMATCH_IDX` and compares the result with `LAST_A` and `LAST_B`.

* Disagrees with exactly one RP: that RP is the suspect.
* Agrees with neither: both are suspect. Repair A first, re-test, then B.
* Agrees with both: impossible if the comparator fired. Log it as a
  comparator/capture fault.

Limitations: the reference only checks the captured window. A common-mode
fault (both RPs wrong in the same way) is invisible to DMR. A transient may
have cleared before the re-test.
