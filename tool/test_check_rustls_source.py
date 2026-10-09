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


class TokioSourceGateTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / "tokio-rustls/src/example.rs"
        self.source.parent.mkdir(parents=True)
        self.source.write_bytes(b"audited Tokio source")
        self.lock = self.root / "tokio-rustls/Cargo.lock"
        self.lock.write_bytes(b"published lock")
        self.manifest = self.root / "tokio-rustls-source-manifest.json"
        self.manifest.write_text(json.dumps({
            "files": {path.relative_to(self.root).as_posix(): {
                "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                "upstream_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            } for path in (self.source, self.lock)},
            "modified_upstream_files": [],
        }))

    def check(self):
        return check(self.root, "tokio-rustls-source-manifest.json", ("tokio-rustls",), ())

    def test_build_outputs_are_allowed(self):
        build = self.root / "tokio-rustls/target/debug/library"
        build.parent.mkdir(parents=True)
        build.write_bytes(b"generated output")
        self.assertEqual(self.check(), [])

    def test_published_lock_change_is_rejected(self):
        self.lock.write_bytes(b"updated dependency")
        self.assertIn("source digest mismatch: tokio-rustls/Cargo.lock", self.check())

    def test_source_change_is_rejected(self):
        self.source.write_bytes(b"unaudited change")
        self.assertIn("source digest mismatch: tokio-rustls/src/example.rs", self.check())

    def test_missing_source_is_rejected(self):
        self.source.unlink()
        self.assertIn("missing or non-regular source: tokio-rustls/src/example.rs", self.check())

    def test_added_source_is_rejected(self):
        (self.source.parent / "unexpected.rs").write_bytes(b"extra source")
        self.assertIn("unexpected source: tokio-rustls/src/unexpected.rs", self.check())

    def test_symlinked_source_directory_is_rejected(self):
        target = self.root / "other"
        self.source.parent.rename(target)
        self.source.parent.symlink_to(target, target_is_directory=True)
        self.assertIn("missing or non-regular source: tokio-rustls/src/example.rs", self.check())

    def test_modified_file_inventory_is_rejected(self):
        manifest = json.loads(self.manifest.read_text())
        manifest["modified_upstream_files"] = ["tokio-rustls/src/example.rs"]
        self.manifest.write_text(json.dumps(manifest))
        self.assertIn("modified upstream file list disagrees with digests", self.check())


if __name__ == "__main__":
    unittest.main()
