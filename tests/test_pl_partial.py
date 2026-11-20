"""Off-board tests for .bit parsing / .bin conversion (no PYNQ needed)."""
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "pynq"))
from selfheal.pl_partial import SYNC_BIN, bit_to_bin_bytes, parse_bit  # noqa: E402


def make_bit(config: bytes) -> bytes:
    def field(key, s):
        b = s.encode() + b"\x00"
        return key.encode() + len(b).to_bytes(2, "big") + b
    hdr = (b"\x00\x09" + bytes.fromhex("0ff00ff00ff00ff000") + b"\x00\x01"
           + field("a", "m0_top;UserID=0XFFFFFFFF;Version=2020.2")
           + field("b", "7z020clg400") + field("c", "2026/11/19") + field("d", "12:00:00"))
    return hdr + b"e" + len(config).to_bytes(4, "big") + config


CONFIG = (b"\xff" * 32 + b"\x00\x00\x00\xbb\x11\x22\x00\x44" + b"\xff" * 8
          + b"\xaa\x99\x55\x66" + b"\x20\x00\x00\x00" + bytes(range(16)))


class TestBit(unittest.TestCase):
    def test_parse_fields(self):
        h = parse_bit(make_bit(CONFIG))
        self.assertEqual(h["b"], "7z020clg400")
        self.assertEqual(h["data"], CONFIG)

    def test_bin_is_word_swapped(self):
        out = bit_to_bin_bytes(make_bit(CONFIG))
        self.assertEqual(len(out), len(CONFIG))
        self.assertIn(SYNC_BIN, out)
        for i in range(0, len(CONFIG), 4):
            self.assertEqual(out[i:i + 4], CONFIG[i:i + 4][::-1])

    def test_rejects_non_bitstream(self):
        with self.assertRaises(ValueError):
            bit_to_bin_bytes(make_bit(b"\x00" * 64))

    def test_rejects_truncated(self):
        with self.assertRaises(ValueError):
            parse_bit(make_bit(CONFIG)[:-5])


if __name__ == "__main__":
    unittest.main()
