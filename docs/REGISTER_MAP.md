# AXI-Lite register map: DRAFT (implemented from M3)

Single source of truth for the human reader. `hdl/regs_pkg.vh` and
`pynq/selfheal/regs.py` are hand-written from this table, and
`tests/test_regmap.py` asserts they agree on every offset and field (agreed
in place of a generator).

Clock: 100 MHz FCLK0. Timestamps are 32-bit cycle counts, which wrap after
42.9 s; any single recovery longer than that is reported as invalid.

| Off | Name | Acc | Fields |
|---|---|---|---|
| 0x00 | CTRL | RW | [0] enable, [1] clear_errors (self-clearing), [2] freeze_A, [3] freeze_B, [5:4] simplex_sel (00 DMR, 01 A only, 10 B only, 11 none) |
| 0x04 | STATUS | RO | [0] mismatch_latched, [1] A_decoupled, [2] B_decoupled, [3] busy |
| 0x08 | MISMATCH_COUNT | RO | mismatches since last clear |
| 0x0C | MISMATCH_IDX | RO | sample index of first mismatch after clear |
| 0x10 | LAST_A | RO | RP_A output at first mismatch |
| 0x14 | LAST_B | RO | RP_B output at first mismatch |
| 0x18 | DECOUPLE | RW | [0] decouple_A, [1] decouple_B |
| 0x1C | SAMPLE_COUNT | RO | samples compared since clear |
| 0x20 | INJECT | RW | [0] arm_A, [1] arm_B (read by faulty RMs), [8] transient_A, [9] transient_B (static-side XOR, cleared on recouple) |
| 0x24 | RM_ID | RO | [7:0] RP_A RM ID, [15:8] RP_B RM ID; reads 0 while that RP is decoupled |
| 0x28 | TIMER_CTRL | RW | [0] arm, [1] clear (self-clearing) |
| 0x2C | T_DETECT | RO | free-running counter latched on first mismatch while armed |
| 0x30 | T_REPAIR | RO | counter latched on the first DECOUPLE 1->0 edge after T_DETECT |
| 0x34 | TIMER_NOW | RO | free-running counter |
| 0x38 | BUILD_ID | RO | static build identifier; Python refuses partials from another build |

Hardware recovery latency = `(T_REPAIR - T_DETECT) / 100` us. Python also
records wall-clock time for the same interval. The difference between the two
is OS, interrupt and driver overhead, reported as its own result.

Note: T_REPAIR marks the recouple, which software triggers after it has
verified the load. So the hardware figure covers detection through
reconfiguration and re-coupling, including PS decision time. It is not just
the reconfiguration time; that is measured separately in `reconfig.py`.
