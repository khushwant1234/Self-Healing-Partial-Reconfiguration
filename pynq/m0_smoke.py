#!/usr/bin/env python3
"""Milestone 0 on-board smoke test: full load, then swap RMs with partials.

STATUS: UNTESTED ON HARDWARE.

Run on the board, as root, from the repo's pynq/ directory:
    sudo -E python3 m0_smoke.py --bits ../bitstreams/m0
    sudo -E python3 m0_smoke.py --bits ../bitstreams/m0 --method sysfs
    sudo -E python3 m0_smoke.py --bits ../bitstreams/m0 --blink 10

What it checks:
  1. full bitstream loads; RM_ID reads 0xA1 (inv); output == ~input
  2. decouple=1 forces output and RM_ID to 0
  3. partial rm_buf loads; RM_ID 0xB2; output == input
  4. partial rm_inv loads back; RM_ID 0xA1; output == ~input
  5. N more swaps, reporting reconfiguration time per load
Exit code 0 only if every check passes.
"""
import argparse
import os
import statistics
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from selfheal.pl_partial import bit_info, load_partial, mgr_state  # noqa: E402

RM_IDS = {"inv": 0xA1, "buf": 0xB2}
PATTERNS = [0x00000000, 0xFFFFFFFF, 0x12345678, 0xA5A5A5A5, 0x0000_0005]
MASK = 0xFFFFFFFF

# AXI GPIO register offsets (PG144)
GPIO_DATA, GPIO2_DATA = 0x0, 0x8

failures = []


def check(cond, what):
    print(("  PASS  " if cond else "  FAIL  ") + what)
    if not cond:
        failures.append(what)


def find_ip(ip_dict, name):
    for k, v in ip_dict.items():
        if k == name or k.endswith("/" + name):
            return v
    raise KeyError(f"{name} not in overlay ip_dict: {sorted(ip_dict)}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bits", default="../bitstreams/m0")
    ap.add_argument("--method", default="auto", choices=["auto", "pynq", "sysfs"])
    ap.add_argument("--swaps", type=int, default=10)
    ap.add_argument("--blink", type=float, default=0.0,
                    help="afterwards, alternate RMs for this many seconds (watch LD0-LD3)")
    a = ap.parse_args()

    if os.geteuid() != 0:
        sys.exit("run with sudo: the FPGA manager and /lib/firmware need root")

    import pynq
    from pynq import MMIO, Overlay
    print(f"pynq {pynq.__version__}; fpga_manager state: {mgr_state()}")

    full = os.path.join(a.bits, "m0_static.bit")
    part = {rm: os.path.join(a.bits, f"rm_{rm}_partial.bit") for rm in RM_IDS}
    for p in [full, *part.values()]:
        info = bit_info(p)
        print(f"  {os.path.basename(p):24s} {info['config_bytes']:>9d} B  "
              f"part={info['part']}  built {info['date']} {info['time']}")

    # ---- 1. full bitstream ---------------------------------------------
    print("\n[1] loading full bitstream (static + inv)")
    t = time.perf_counter()
    ol = Overlay(full)
    print(f"  full load: {(time.perf_counter() - t) * 1e3:.1f} ms (includes PYNQ overhead)")
    gd = MMIO(find_ip(ol.ip_dict, "gpio_data")["phys_addr"], 0x1000)
    gc = MMIO(find_ip(ol.ip_dict, "gpio_ctrl")["phys_addr"], 0x1000)

    def decouple(on):
        gc.write(GPIO_DATA, 1 if on else 0)

    def rm_id():
        return gc.read(GPIO2_DATA) & 0xFF

    def xfer(v):
        gd.write(GPIO_DATA, v)
        return gd.read(GPIO2_DATA) & MASK

    def verify(rm, tag):
        decouple(False)
        check(rm_id() == RM_IDS[rm], f"{tag}: RM_ID = 0x{rm_id():02X}, expect 0x{RM_IDS[rm]:02X}")
        expect = (lambda p: ~p & MASK) if rm == "inv" else (lambda p: p)
        got = [(p, xfer(p)) for p in PATTERNS]
        bad = [(p, o) for p, o in got if o != expect(p)]
        check(not bad, f"{tag}: {rm} transfer function on {len(PATTERNS)} patterns"
              + (f" -- mismatches {[(hex(p), hex(o)) for p, o in bad]}" if bad else ""))

    def swap(rm):
        decouple(True)
        r = load_partial(part[rm], a.method)
        decouple(False)
        return r

    verify("inv", "after full load")

    # ---- 2. decoupler ----------------------------------------------------
    print("\n[2] decoupler")
    decouple(True)
    check(xfer(0x12345678) == 0 and rm_id() == 0, "decouple=1 forces output and RM_ID to 0")
    decouple(False)

    # ---- 3/4. partial swaps ---------------------------------------------
    print("\n[3] partial: inv -> buf")
    r = swap("buf")
    print(f"  method={r.method} prepare={r.prepare_s * 1e3:.1f} ms load={r.load_s * 1e3:.2f} ms")
    verify("buf", "after partial buf")

    print("\n[4] partial: buf -> inv")
    r = swap("inv")
    print(f"  method={r.method} prepare={r.prepare_s * 1e3:.1f} ms load={r.load_s * 1e3:.2f} ms")
    verify("inv", "after partial inv")

    # ---- 5. timing -------------------------------------------------------
    print(f"\n[5] {a.swaps} more swaps, timing the configuration write only")
    loads = []
    for i in range(a.swaps):
        rm = "buf" if i % 2 == 0 else "inv"
        loads.append(swap(rm).load_s * 1e3)
        if rm_id() != RM_IDS[rm]:
            check(False, f"swap {i}: RM_ID 0x{rm_id():02X} after loading {rm}")
            break
    if loads:
        print(f"  load ms: min {min(loads):.2f}  median {statistics.median(loads):.2f}  "
              f"max {max(loads):.2f}  (n={len(loads)}, method={a.method})")
    verify("buf" if a.swaps % 2 else "inv", "after timing loop")

    # ---- optional LED blink ---------------------------------------------
    if a.blink > 0:
        print(f"\n[blink] LD3..LD0 should alternate 1010 (inv) / 0101 (buf) for {a.blink:.0f} s")
        gd.write(GPIO_DATA, 0x5)
        end, rm = time.time() + a.blink, "buf"
        while time.time() < end:
            swap(rm)
            gd.write(GPIO_DATA, 0x5)
            rm = "inv" if rm == "buf" else "buf"
            time.sleep(1.0)

    print("\n" + ("M0 SMOKE TEST: ALL PASS" if not failures
                  else f"M0 SMOKE TEST: {len(failures)} FAILURE(S)"))
    sys.exit(0 if not failures else 1)


if __name__ == "__main__":
    main()
