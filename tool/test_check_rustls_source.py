#!/usr/bin/env python3
"""Failure controls for the vendored-source verification gate."""

import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from check_rustls_source import check


class SourceGateTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / "rustls/src/example.rs"
        self.source.parent.mkdir(parents=True)
        self.source.write_bytes(b"audited source")
        digest = hashlib.sha256(self.source.read_bytes()).hexdigest()
        (self.root / "rustls-source-manifest.json").write_text(json.dumps({
            "files": {"rustls/src/example.rs": {
                "sha256": digest, "upstream_sha256": digest,
            }},
            "modified_upstream_files": [],
        }))

    def test_build_outputs_are_allowed(self):
        build = self.root / "rustls/target/debug/library"
        build.parent.mkdir(parents=True)
        build.write_bytes(b"generated output")
        (self.root / "rustls/Cargo.lock").write_text("generated lock")
        self.assertEqual(check(self.root), [])

    def test_source_change_fails(self):
        self.source.write_bytes(b"unaudited change")
        self.assertIn("source digest mismatch: rustls/src/example.rs", check(self.root))

    def test_missing_source_fails(self):
        self.source.unlink()
        self.assertIn("missing or non-regular source: rustls/src/example.rs", check(self.root))

    def test_added_source_fails(self):
        (self.source.parent / "unexpected.rs").write_text("unreviewed source")
        self.assertIn("unexpected source: rustls/src/unexpected.rs", check(self.root))

    def test_symlink_substitution_fails(self):
        target = self.root / "other.rs"
        target.write_bytes(self.source.read_bytes())
        self.source.unlink()
        self.source.symlink_to(target)
        self.assertIn("missing or non-regular source: rustls/src/example.rs", check(self.root))


if __name__ == "__main__":
    unittest.main()
