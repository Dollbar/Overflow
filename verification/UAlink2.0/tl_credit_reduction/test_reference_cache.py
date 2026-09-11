"""Run python3 -m unittest discover -s verification/tl_credit_reduction
-p test_reference_cache.py. Check isolated reference use and legacy corruption
rejection on real temporary directories. Next run the actual SAT entry.
"""
from pathlib import Path
import hashlib
import json
import tempfile
import unittest

from run_equivalence import LEGACY_REFERENCE, cache_legacy_reference


class ReferenceCacheTests(unittest.TestCase):
    def test_other_reference_leaves_existing_legacy_bytes_untouched(self):
        with tempfile.TemporaryDirectory() as name:
            folder = Path(name)
            cache_legacy_reference(folder, LEGACY_REFERENCE, b"legacy rtl")
            before = {p.name: p.read_bytes() for p in folder.iterdir()}
            cache_legacy_reference(folder, "other immutable commit", b"new rtl")
            self.assertEqual(before, {p.name: p.read_bytes() for p in folder.iterdir()})

    def test_other_reference_does_not_claim_empty_legacy_cache(self):
        with tempfile.TemporaryDirectory() as name:
            folder = Path(name)
            cache_legacy_reference(folder, "other immutable commit", b"new rtl")
            self.assertEqual([], list(folder.iterdir()))

    def test_legacy_creates_bound_pair_and_rejects_corruption(self):
        with tempfile.TemporaryDirectory() as name:
            folder = Path(name)
            cache_legacy_reference(folder, LEGACY_REFERENCE, b"legacy rtl")
            self.assertEqual((folder / "original.v").read_bytes(), b"legacy rtl")
            self.assertEqual(json.loads((folder / "original.json").read_text()),
                             {"commit": LEGACY_REFERENCE,
                              "sha256": hashlib.sha256(b"legacy rtl").hexdigest()})
            (folder / "original.v").write_bytes(b"changed rtl")
            with self.assertRaises(ValueError):
                cache_legacy_reference(folder, LEGACY_REFERENCE, b"legacy rtl")

    def test_legacy_rejects_incomplete_cache_pair(self):
        with tempfile.TemporaryDirectory() as name:
            folder = Path(name)
            (folder / "original.v").write_bytes(b"legacy rtl")
            with self.assertRaises(ValueError):
                cache_legacy_reference(folder, LEGACY_REFERENCE, b"legacy rtl")


if __name__ == "__main__":
    unittest.main()
