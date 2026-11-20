"""Partial-bitstream loading on Zynq-7000 under PYNQ.

STATUS: UNTESTED ON HARDWARE (written before the board's PYNQ version is known).

Two load paths, chosen at run time:

* ``pynq``  -- ``pynq.Bitstream(path, partial=True).download()``. Exists on
  PYNQ 2.5+; behaviour around PL-server bookkeeping differs by version.
* ``sysfs`` -- talk to the Linux FPGA manager directly: convert .bit -> .bin
  (strip header, byte-swap each 32-bit word), copy to /lib/firmware, set
  ``flags`` to 1 (partial), write the file name to ``firmware``.

``auto`` tries ``pynq`` and falls back to ``sysfs`` ONLY when the PYNQ API is
missing (TypeError/AttributeError). Any other error from a real download
attempt is raised: a half-applied partial must not be papered over.

Must run as root (sudo), because both paths write to /sys and /lib/firmware.
"""
from __future__ import annotations

import array
import os
import time
from dataclasses import dataclass

FPGA_MGR = "/sys/class/fpga_manager/fpga0"
FIRMWARE_DIR = "/lib/firmware"
SYNC_BIT = b"\xaa\x99\x55\x66"  # sync word as it appears in a .bit
SYNC_BIN = b"\x66\x55\x99\xaa"  # after per-word byte swap (what zynq-fpga wants)


@dataclass
class LoadResult:
    path: str
    method: str
    prepare_s: float   # header strip / conversion / object construction
    load_s: float      # the actual configuration write
    mgr_state: str


# --------------------------------------------------------------------------
# .bit parsing / conversion
# --------------------------------------------------------------------------
def parse_bit(data: bytes) -> dict:
    """Parse a Xilinx .bit header. Returns fields a..d and the raw config data."""
    if len(data) < 16:
        raise ValueError("file too short to be a .bit")
    l0 = int.from_bytes(data[0:2], "big")
    pos = 2 + l0          # skip magic field (normally 9 bytes)
    pos += 2              # 0x0001
    fields = {}
    while pos < len(data):
        key = chr(data[pos]); pos += 1
        if key in "abcd":
            n = int.from_bytes(data[pos:pos + 2], "big"); pos += 2
            fields[key] = data[pos:pos + n].rstrip(b"\x00").decode("ascii", "replace")
            pos += n
        elif key == "e":
            n = int.from_bytes(data[pos:pos + 4], "big"); pos += 4
            fields["data"] = data[pos:pos + n]
            if len(fields["data"]) != n:
                raise ValueError(f"truncated .bit: expected {n} config bytes")
            return fields
        else:
            raise ValueError(f"unexpected .bit header key {key!r} at offset {pos - 1}")
    raise ValueError("no configuration data section ('e') found")


def bit_to_bin_bytes(data: bytes) -> bytes:
    """Header-stripped, 32-bit-word byte-swapped image for the zynq FPGA manager."""
    raw = parse_bit(data)["data"]
    if len(raw) % 4:
        raise ValueError("configuration data is not a whole number of 32-bit words")
    if SYNC_BIT not in raw[:256]:
        raise ValueError("sync word AA995566 not found -- not a Xilinx 7-series bitstream?")
    words = array.array("I", raw)
    assert words.itemsize == 4
    words.byteswap()
    out = words.tobytes()
    assert SYNC_BIN in out[:256]
    return out


def bit_info(path: str) -> dict:
    with open(path, "rb") as f:
        hdr = parse_bit(f.read())
    return {"design": hdr.get("a"), "part": hdr.get("b"),
            "date": hdr.get("c"), "time": hdr.get("d"),
            "config_bytes": len(hdr["data"])}


# --------------------------------------------------------------------------
# loaders
# --------------------------------------------------------------------------
def _read(p: str) -> str:
    with open(p) as f:
        return f.read().strip()


def _write(p: str, s: str) -> None:
    with open(p, "w") as f:
        f.write(s)


def mgr_state() -> str:
    try:
        return _read(os.path.join(FPGA_MGR, "state"))
    except OSError as e:
        return f"unreadable ({e})"


def load_partial_sysfs(bit_path: str) -> LoadResult:
    t0 = time.perf_counter()
    with open(bit_path, "rb") as f:
        image = bit_to_bin_bytes(f.read())
    name = os.path.basename(bit_path) + ".bin"
    with open(os.path.join(FIRMWARE_DIR, name), "wb") as f:
        f.write(image)
    t1 = time.perf_counter()
    _write(os.path.join(FPGA_MGR, "flags"), "1")       # FPGA_MGR_PARTIAL_RECONFIG
    try:
        _write(os.path.join(FPGA_MGR, "firmware"), name)
    finally:
        t2 = time.perf_counter()
        _write(os.path.join(FPGA_MGR, "flags"), "0")
    state = mgr_state()
    if state != "operating":
        raise RuntimeError(f"FPGA manager state after partial load is {state!r}")
    return LoadResult(bit_path, "sysfs", t1 - t0, t2 - t1, state)


def load_partial_pynq(bit_path: str) -> LoadResult:
    from pynq import Bitstream  # imported lazily so the module works off-board
    t0 = time.perf_counter()
    bs = Bitstream(bit_path, partial=True)   # TypeError on PYNQ without partial support
    t1 = time.perf_counter()
    bs.download()
    t2 = time.perf_counter()
    state = mgr_state()
    if state != "operating":
        raise RuntimeError(f"FPGA manager state after partial load is {state!r}")
    return LoadResult(bit_path, "pynq.Bitstream", t1 - t0, t2 - t1, state)


def load_partial(bit_path: str, method: str = "auto") -> LoadResult:
    if not os.path.isfile(bit_path):
        raise FileNotFoundError(bit_path)
    if method == "sysfs":
        return load_partial_sysfs(bit_path)
    if method == "pynq":
        return load_partial_pynq(bit_path)
    if method != "auto":
        raise ValueError(f"unknown method {method!r}")
    try:
        return load_partial_pynq(bit_path)
    except (TypeError, AttributeError, ImportError) as e:
        print(f"[pl_partial] PYNQ partial API unavailable ({e!r}); using sysfs path")
        return load_partial_sysfs(bit_path)
