#!/usr/bin/env python3
"""Integrity controls for the browser-readable conformance fixture bundle."""

import base64
import hashlib
import json
import re
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import build_conformance_fixtures as bundle


class FixtureBundleTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.root = self.directory / "fixtures"
        self.root.mkdir()
        self.output = self.directory / "bundle.dart"
        self.manifest = self.directory / "bundle.json"
        self.data = b'{"number":9007199254740991,"spelling":1e+00,"text":"\xc3\x9f"}\r\n'
        (self.root / "vector.json").write_bytes(self.data)

    def build(self, check=False):
        return bundle.build(self.root, self.output, self.manifest, check=check)

    def test_preserves_exact_bytes_not_reencoded_json(self):
        self.assertEqual(self.build(), 1)
        encoded = re.findall(r"^      '([^']*)'", self.output.read_text(), re.M)
        self.assertEqual(base64.b64decode("".join(encoded)), self.data)
        metadata = json.loads(self.manifest.read_text())
        self.assertEqual(metadata["sourceHashes"], {
            "vector.json": hashlib.sha256(self.data).hexdigest(),
        })
        self.assertEqual(metadata["bundleSha256"], hashlib.sha256(self.output.read_bytes()).hexdigest())
        self.assertEqual(self.build(check=True), 1)

    def test_every_file_is_inventoried_in_stable_order(self):
        (self.root / "nested").mkdir()
        (self.root / "nested" / "README.md").write_bytes(b"metadata")
        (self.root / "SCHEMA.json").write_bytes(b"{}")
        self.assertEqual(self.build(), 3)
        before = self.output.read_bytes(), self.manifest.read_bytes()
        self.build()
        self.assertEqual(before, (self.output.read_bytes(), self.manifest.read_bytes()))
        self.assertEqual(list(json.loads(before[1])["sourceHashes"]), [
            "SCHEMA.json", "nested/README.md", "vector.json",
        ])

    def test_changed_added_and_deleted_files_reject_stale_bundle(self):
        for change in ("changed", "added", "deleted"):
            with self.subTest(change=change):
                source = self.root / "vector.json"
                source.write_bytes(self.data)
                self.build()
                before = self.output.read_bytes(), self.manifest.read_bytes()
                extra = self.root / "extra.json"
                if change == "changed":
                    source.write_bytes(b"changed")
                elif change == "added":
                    extra.write_bytes(b"new")
                else:
                    source.unlink()
                with self.assertRaises(ValueError):
                    self.build(check=True)
                self.assertEqual(before, (self.output.read_bytes(), self.manifest.read_bytes()))
                extra.unlink(missing_ok=True)

    def test_corrupt_or_missing_outputs_fail_read_only_check(self):
        for name in ("output", "manifest"):
            for corruption in (b"modified", None):
                with self.subTest(name=name, corruption=corruption):
                    self.build()
                    target = getattr(self, name)
                    if corruption is None:
                        target.unlink()
                    else:
                        target.write_bytes(corruption)
                    with self.assertRaises(ValueError):
                        self.build(check=True)
                    self.assertEqual(target.read_bytes() if target.exists() else None, corruption)

    def test_empty_inventory_fails_closed(self):
        (self.root / "vector.json").unlink()
        with self.assertRaisesRegex(ValueError, "Empty"):
            self.build()
        self.assertFalse(self.output.exists())

    def test_symlink_file_and_directory_are_rejected(self):
        for directory in (False, True):
            with self.subTest(directory=directory):
                target = self.directory / "target"
                if directory:
                    target.mkdir()
                else:
                    target.write_bytes(b"outside")
                link = self.root / "linked"
                try:
                    link.symlink_to(target, target_is_directory=directory)
                except OSError as error:
                    self.skipTest(f"Symlinks unavailable: {error}")
                with self.assertRaisesRegex(ValueError, "Symlink"):
                    self.build()
                link.unlink()
                target.rmdir() if directory else target.unlink()

    def test_unsafe_names_are_not_silently_omitted(self):
        (self.root / "quote'name.json").write_bytes(b"{}")
        with self.assertRaisesRegex(ValueError, "Unsupported"):
            self.build()

    def test_source_drift_during_generation_is_rejected_before_writes(self):
        with patch.object(bundle, "collect", side_effect=[{"x": b"old"}, {"x": b"new"}]):
            with self.assertRaisesRegex(ValueError, "changed during"):
                self.build()
        self.assertFalse(self.output.exists())
        self.assertFalse(self.manifest.exists())

    def test_empty_file_is_retained(self):
        (self.root / "vector.json").write_bytes(b"")
        self.build()
        self.assertIn("      '',", self.output.read_text())
        self.assertEqual(list(json.loads(self.manifest.read_text())["sourceHashes"]), ["vector.json"])

    def test_repository_bundle_is_current(self):
        count = bundle.build(bundle.FIXTURES, bundle.OUTPUT, bundle.MANIFEST, check=True)
        self.assertEqual(count, len(bundle.collect(bundle.FIXTURES)))


if __name__ == "__main__":
    unittest.main()
